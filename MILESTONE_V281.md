# Rosa V2.8.1 milestone — Context instead of directories

## Goal
Remove Guest Profiles and Registration Center as owner destinations without deleting either capability.

## Implemented
- Guest Profiles removed from Settings navigation.
- Registration Center removed from Settings navigation.
- Today surfaces registration risks only when action is relevant.
- Today registration risk window includes arrivals today and tomorrow.
- Reservation detail now returns contextual primary-guest memory: stay count, previous stays and operational preferences.
- Reservation workspace shows returning-guest context and full guest-history access.
- Reservation Preparation has a useful registration card with progress and individual guest records.
- Manual `Prepare reminder` creates a Reception draft and cannot externally send.
- Reception displays returning-guest context for linked conversations.
- Universal search guest results show stay count and remain the scalable historical retrieval path.
- Legacy direct `guests` / `registration` navigation routes resolve to Search / Today rather than restoring directory pages.

## Deliberately unchanged
The guest-profile and registration backend data models remain intact. VENDÉGEM compliance boundaries remain unchanged.
