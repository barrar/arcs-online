# Web deployment

The project is selected in `.firebaserc` as `arcs-online-jeremiah-2026`. Firebase CLI access is working. The [hosted preview](https://arcs-online-jeremiah-2026.web.app), Firestore rules, Authentication providers, and five callable lobby Functions have been deployed. The Firebase project is on Blaze. The app is not yet a playable ARCS match.

Anonymous and email/password sign-in are declared in `firebase.json` and were deployed with `firebase deploy --only auth`. Google sign-in remains unconfigured because it requires an approved support email and OAuth brand setup. The web UI supports linking, but that option will fail until the provider is enabled. Android and iPhone builds are deferred at the user's request.

For subsequent deployments, run from the project root with Node.js 22 or newer and a current npm-installed Firebase CLI:

```sh
npm --prefix functions ci
npm --prefix functions run check
firebase deploy --only auth,functions --project arcs-online-jeremiah-2026
flutter build web --release
firebase deploy --only firestore,hosting --project arcs-online-jeremiah-2026
```

The first Functions deploy created all five endpoints but returned a nonzero exit solely because Artifact Registry had no cleanup policy. A 30-day policy was then set with `firebase functions:artifacts:setpolicy --location us-west1 --days 30 --force`; `firebase functions:list` verified the endpoints. A hosted-browser guest created a private two-seat lobby, and `node functions/security/smoke-production.cjs INVITE_CODE` verified a second guest's join, permitted private read, ready status, and departure. The host then left the disposable lobby. A separate public 48-hour async lobby appeared in discovery and disappeared after its host left.

Match start is intentionally disabled until full rules implementation and verification are complete. In particular, setup, standard actions, battle, Court effects, chapter transitions, and full-game tests remain outstanding.
