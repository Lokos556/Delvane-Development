# Rosa V2.6 quick test

1. Start `START_ROSA.bat` and sign in as the owner.
2. Open Intelligence and ask **Anything concerning tomorrow?**. Refresh the page; the conversation should remain.
3. Ask **What about Terra?** and confirm Rosa answers from the current Terra context.
4. In default OBSERVE mode, use the suggested prompt **Anna called in sick. Move today's cleaning to Erika.** Rosa should show an **Observe only** proposal and must not actually change the cleaner assignment.
5. Open Settings → Simulation and switch to ASSIST. Ask the same staffing question. Rosa should show Approve/Decline. Approve it, then inspect Operations/cleaning: the eligible task(s) should be assigned to Erika.
6. Return to Train Rosa/authority rules. Setting `reassign_cleaning` to Never must block the action even if the organization is Autonomous.
7. Start a New chat and confirm the previous conversation remains server-side.
8. Switch UI language and confirm all new V2.6 controls translate.

Optional external AI: configure environment variables from `.env.example`; never paste a production API key into frontend JavaScript or a public file.
