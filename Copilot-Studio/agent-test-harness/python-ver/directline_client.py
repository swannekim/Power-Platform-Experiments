"""
directline_client.py
---------------------
A thin client for talking to a Microsoft Copilot Studio agent over the
Direct Line API (v3.0). This is the same channel your agent's web chat uses,
so anything a real user can do, this client can do — which makes it perfect
for automated testing.

Flow (per Microsoft Learn "Test conversational agents using Direct Line"):
  1. Get a Direct Line token
       - from a Copilot Studio *token endpoint* (no secret), OR
       - by generating one from a Direct Line *secret*.
  2. Start a conversation -> get a conversationId.
  3. Send an activity (the user's message) via HTTP POST.
  4. Poll the activities endpoint (HTTP GET) until the agent has finished
     replying, tracking timing for every step.

We use HTTP GET polling rather than WebSockets because it is simpler and
deterministic for a test harness. Microsoft's guidance supports both; GET
polling is the documented fallback and is easier to reason about in CI.
"""

from __future__ import annotations

import time
import uuid
import requests
from dataclasses import dataclass, field


# The global Direct Line base. Some tenants/regions use a regional host
# (e.g. https://europe.directline.botframework.com). Override via config if so.
DEFAULT_DIRECTLINE_BASE = "https://directline.botframework.com/v3/directline"


@dataclass
class Timings:
    """Per-step latency, in seconds. These are the numbers Microsoft's guidance
    tells you to track for performance testing."""
    generate_token: float = 0.0
    start_conversation: float = 0.0
    send_activity: float = 0.0
    receive_response: float = 0.0  # user message -> agent's LAST reply

    def as_dict(self) -> dict:
        return {
            "generate_token_s": round(self.generate_token, 3),
            "start_conversation_s": round(self.start_conversation, 3),
            "send_activity_s": round(self.send_activity, 3),
            "receive_response_s": round(self.receive_response, 3),
        }


@dataclass
class Turn:
    """The result of sending one user message and collecting the agent's reply."""
    user_text: str
    bot_messages: list = field(default_factory=list)   # list[str]
    bot_activities: list = field(default_factory=list)  # raw activity dicts
    timings: Timings = field(default_factory=Timings)

    @property
    def combined_reply(self) -> str:
        """All the agent's message texts for this turn, joined. Handy for
        keyword / contains assertions."""
        return "\n".join(m for m in self.bot_messages if m)

    @property
    def activity_types(self) -> set:
        return {a.get("type") for a in self.bot_activities}

    @property
    def has_card(self) -> bool:
        return any(a.get("attachments") for a in self.bot_activities)


class DirectLineClient:
    def __init__(
        self,
        token_endpoint: str | None = None,
        secret: str | None = None,
        directline_base: str = DEFAULT_DIRECTLINE_BASE,
        user_id: str | None = None,
        # How long to wait, after the last bot frame, before deciding the agent
        # is "done" for this turn. Copilot Studio has no explicit "last message"
        # signal, so we treat a quiet period as end-of-turn.
        quiet_period_s: float = 2.5,
        # Hard ceiling for one turn (protects against a hung agent / long API call).
        turn_timeout_s: float = 45.0,
        poll_interval_s: float = 0.75,
    ):
        if not token_endpoint and not secret:
            raise ValueError("Provide either token_endpoint or secret.")
        self.token_endpoint = token_endpoint
        self.secret = secret
        self.base = directline_base.rstrip("/")
        self.user_id = user_id or f"user-{uuid.uuid4().hex[:8]}"
        self.quiet_period_s = quiet_period_s
        self.turn_timeout_s = turn_timeout_s
        self.poll_interval_s = poll_interval_s

        self.token: str | None = None
        self.conversation_id: str | None = None
        self._watermark: str | None = None
        self.session_timings = Timings()

    # ---- 1. token -------------------------------------------------------
    def _get_token(self) -> float:
        t0 = time.monotonic()
        if self.token_endpoint:
            # Copilot Studio token endpoint: a simple GET returns a token.
            r = requests.get(self.token_endpoint, timeout=30)
            r.raise_for_status()
            self.token = r.json()["token"]
        else:
            # Generate from a Direct Line secret.
            r = requests.post(
                f"{self.base}/tokens/generate",
                headers={"Authorization": f"Bearer {self.secret}"},
                timeout=30,
            )
            r.raise_for_status()
            self.token = r.json()["token"]
        return time.monotonic() - t0

    # ---- 2. start conversation -----------------------------------------
    def _start_conversation(self) -> float:
        t0 = time.monotonic()
        r = requests.post(
            f"{self.base}/conversations",
            headers={"Authorization": f"Bearer {self.token}"},
            timeout=30,
        )
        r.raise_for_status()
        self.conversation_id = r.json()["conversationId"]
        return time.monotonic() - t0

    def start(self) -> Timings:
        """Get a token and open a conversation. Call once per test 'session'."""
        self.session_timings.generate_token = self._get_token()
        self.session_timings.start_conversation = self._start_conversation()
        # Drain the greeting so it isn't attributed to the first user turn.
        self._drain_initial()
        return self.session_timings

    def _headers(self) -> dict:
        return {
            "Authorization": f"Bearer {self.token}",
            "Content-Type": "application/json",
        }

    def _drain_initial(self):
        """Read (and discard) any welcome/greeting activities the agent sends
        before the user says anything, and advance the watermark past them."""
        deadline = time.monotonic() + self.quiet_period_s + 3
        while time.monotonic() < deadline:
            acts, _ = self._get_activities()
            if acts and any(a.get("inputHint") == "acceptingInput" for a in acts):
                break
            time.sleep(self.poll_interval_s)

    # ---- 3. send activity ----------------------------------------------
    def _post_activity(self, text: str) -> tuple[str, float]:
        t0 = time.monotonic()
        r = requests.post(
            f"{self.base}/conversations/{self.conversation_id}/activities",
            headers=self._headers(),
            json={"type": "message", "from": {"id": self.user_id}, "text": text},
            timeout=30,
        )
        r.raise_for_status()
        return r.json()["id"], time.monotonic() - t0

    # ---- 4. receive activities -----------------------------------------
    def _get_activities(self) -> tuple[list, str | None]:
        url = f"{self.base}/conversations/{self.conversation_id}/activities"
        if self._watermark:
            url += f"?watermark={self._watermark}"
        r = requests.get(url, headers=self._headers(), timeout=30)
        r.raise_for_status()
        data = r.json()
        self._watermark = data.get("watermark", self._watermark)
        return data.get("activities", []), self._watermark

    def send(self, text: str) -> Turn:
        """Send one user message and collect the agent's full reply for the turn.

        Response time is measured from just before we POST the user message to
        the moment the agent goes quiet — i.e. the *user-perceived* latency,
        which is what Microsoft's guidance says to report."""
        turn = Turn(user_text=text)
        user_msg_id, send_s = self._post_activity(text)
        turn.timings.send_activity = send_s

        t_user_sent = time.monotonic()
        last_bot_activity_at: float | None = None
        deadline = t_user_sent + self.turn_timeout_s

        while time.monotonic() < deadline:
            acts, _ = self._get_activities()
            for a in acts:
                is_bot = (a.get("from", {}).get("role") == "bot")
                if is_bot and a.get("type") == "message":
                    turn.bot_activities.append(a)
                    if a.get("text"):
                        turn.bot_messages.append(a["text"])
                    last_bot_activity_at = time.monotonic()
                    # An explicit "your turn" signal = agent is done.
                    if a.get("inputHint") == "acceptingInput":
                        deadline = time.monotonic()  # break outer loop
            # If the agent has spoken and then gone quiet, call it done.
            if last_bot_activity_at and (
                time.monotonic() - last_bot_activity_at >= self.quiet_period_s
            ):
                break
            time.sleep(self.poll_interval_s)

        if last_bot_activity_at:
            turn.timings.receive_response = last_bot_activity_at - t_user_sent
        else:
            # No reply at all within the timeout.
            turn.timings.receive_response = self.turn_timeout_s
        return turn
