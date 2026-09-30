# Getting Liv onto other people's phones

TestFlight is the only practical way to hand this app to someone who is not
standing next to you, and it needs a paid Apple Developer Program membership.

**The membership has lapsed.** Team `LG82378GBZ`, enrolled as an Individual,
renewed on 17 July 2026 with auto-renew switched off. The certificate and
provisioning profiles on this machine were issued on 2 August and still look
healthy — they carry a 365-day life, which a free account never gets — but
the portal refuses anything that needs an active membership. Until the annual
fee is paid, everything below the line "Once the membership is active" is
closed.

The people who install it never need an account of their own.

## Until the membership is renewed

Two ways to get the app to someone, neither of them TestFlight.

**If they have a Mac, use the simulator.** No signing, no expiry, no account.

```
./build.sh
```

Send them `shell/ios/build/Liv.app` zipped. They need Xcode installed, then:

```
xcrun simctl boot "iPhone 17" ; open -a Simulator
xcrun simctl install booted Liv.app
xcrun simctl launch booted app.liv.ios
```

This is the least friction by a wide margin. It is not their phone, so it
tells you nothing about how the app feels in a hand.

**If it has to be their iPhone, they sideload it.**

```
./build.sh sideload
```

That writes `shell/ios/build/Liv-sideload.ipa`, unsigned on purpose. Send it
to them. They install [Sideloadly](https://sideloadly.io) (Mac or Windows),
plug the phone in, drag the `.ipa` on, and sign in with **their own** Apple ID
— a free one is fine. AltStore does the same job and can refresh over Wi-Fi.

Then, on the phone, Settings > General > VPN & Device Management > trust the
developer, once.

This works for Liv specifically because it asks for no entitlement a free
Apple ID cannot issue: an application identifier, a team identifier,
`get-task-allow` and a keychain group, and nothing else. An app wanting push
notifications, iCloud or App Groups could not be sideloaded this way.

What they live with, none of it in your control:

| | |
|---|---|
| App stops opening after | 7 days |
| Reinstall needs | their computer and a cable |
| Sideloaded apps per device | 3 |

Seven days is the part people give up on. For one friend testing for a week
it is fine. For anything longer, the 999 kr is the answer.

## Once the membership is active

`./build.sh appstore` does the whole build. Five things have to exist in your
Apple account first, and none of them can be created from a script — each one
needs you signed in.

## The five one-time steps

**1. A distribution certificate.** Xcode > Settings > Accounts > your Apple ID
> Manage Certificates > + > Apple Distribution. This is separate from the
"Apple Development" certificate already in the keychain, and the build refuses
to run without it, by name.

**2. An explicit App ID for `app.liv.ios`**, at developer.apple.com >
Identifiers. One probably exists already, since the development profile is
scoped to that bundle id. Check before creating a second.

**3. The app record**, at appstoreconnect.apple.com > Apps > +. It wants a
name, a primary language, the bundle id, and an SKU (any string you choose;
`liv-ios` is fine). The name has to be unique across the whole App Store, so
plain "Liv" may be taken — the name here is only what testers see, and it can
be changed later.

**4. An App Store provisioning profile**, at developer.apple.com > Profiles >
+ > App Store Connect. Download it into

```
~/Library/Developer/Xcode/UserData/Provisioning Profiles/
```

The build finds it by itself. It tells a store profile from a development one
by the absence of `ProvisionedDevices`: a development profile lists the phones
it is allowed on, a store profile lists none.

**5. An App Store Connect API key**, at appstoreconnect.apple.com > Users and
Access > Integrations > App Store Connect API. Choose the App Manager role.
You get a `.p8` file that downloads **once** and cannot be downloaded again.
Put it here, keeping the filename Apple gives it:

```
~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8
```

Then set two variables, from the key's row in that same page:

```
export LIV_ASC_KEY_ID=<the Key ID>
export LIV_ASC_ISSUER_ID=<the Issuer ID>
```

## Then, every release

```
./build.sh appstore validate
```

builds the `.ipa` and asks Apple to check it without publishing anything. Run
this first; it catches a bad icon or a missing plist key in about a minute.

```
./build.sh appstore upload
```

sends it. The build then takes 5 to 15 minutes to finish processing before it
appears in TestFlight.

In App Store Connect > TestFlight, **internal testers** (up to 100 people who
hold a role on your account) get the build immediately, with no review.
**External testers** (up to 10,000, invited by email or a public link) need a
Beta App Review on the first build, which usually takes a day; later builds
normally pass without another wait.

A TestFlight build stops working 90 days after upload. That is Apple's limit,
not a setting.

## What the build does that Xcode would have done

There is no Xcode project here, so `build.sh appstore` does four things by
hand that Xcode does silently. Each one is a rejection if it is missing.

- **The icon.** `Icon/make-icon.swift` draws the 1024 master, `actool`
  compiles the catalog, and the `CFBundleIcons` keys it reports are merged
  into the plist.
- **Build metadata.** `DTXcode`, `DTSDKBuild`, `BuildMachineOSBuild` and the
  rest. Apple's validator requires them and a hand-assembled bundle has none.
- **Export compliance.** `ITSAppUsesNonExemptEncryption` is set to false, which
  is true for this app and saves answering the question on every upload.
- **The build number.** `CFBundleVersion` is the commit count, so it rises on
  its own. App Store Connect refuses a second upload carrying a number it has
  already seen. Override it with `LIV_BUILD=<n>` if you ever need to.

`CFBundleShortVersionString` — the version people see — is still `0.1` in
`Info-device.plist` and is yours to set by hand.

## The icon is a placeholder

`Icon/make-icon.swift` draws a wordmark on the app's one live colour. It
exists because Apple refuses a build with no icon, not because it is the
mark. Replace the body of `draw` when the real one exists; nothing else in
the pipeline knows what it looks like.
