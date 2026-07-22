# Copilot Studio agent — "Safety Assistant"

Replaces the original app's hand-wired Azure OpenAI chatbot. The agent answers safety questions grounded in
your **own** near-miss history (retrieval over Dataverse), in Korean / English / Japanese.

> Copilot Studio agents are configured in the Copilot Studio portal, not imported from a file. Add the agent
> to the **same solution** so it deploys with everything else.

## Build steps
1. **Copilot Studio** → *Create* → new agent in the target environment. Name it **Safety Assistant**.
2. **Knowledge** → add a knowledge source of type **Dataverse** → table **Near-Miss Reports**
   (add **Corrective Actions** too if you want it to answer "what was done about X"). This grounds answers.
3. **Generative answers**: keep enabled so open questions are answered from knowledge. Optionally add a
   dedicated topic with a **generative-answers node** for "what should I watch out for" style prompts.
4. **Language**: allow the agent to respond in the user's language; test with Korean, English and Japanese.
5. **Instructions** (agent prompt), suggested:
   ```
   You are a workplace-safety assistant for our organisation. Answer using our near-miss
   report history. Be concrete and preventive: cite the kinds of past incidents that
   inform your answer, suggest specific precautions, and never invent incidents. If you
   have no relevant history, say so and give general safe-work guidance. Reply in the
   user's language.
   ```
6. **Test** in the built-in chat, then **Publish**.
7. **Surface it**:
   - In the canvas app: `scrAssistant` → Insert → AI → *Copilot Studio agent* → select **Safety Assistant**.
   - In **Microsoft Teams**: publish the agent to Teams so workers can ask from chat.

## Notes
- Answers reflect what's in Dataverse *now*, so they improve automatically as reports accumulate — no
  re-training, unlike the original approach.
- Respect security: the agent should honour Dataverse row security so users only see what they're permitted to.
