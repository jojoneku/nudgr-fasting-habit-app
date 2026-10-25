## ADDED Requirements

### Requirement: App lock needs a signed-in account
The system SHALL offer the app lock only to a signed-in user. When no user is signed in, the Security section SHALL show "Sign in to use app lock" and no lock controls.

#### Scenario: Guest user on mobile
- **WHEN** a user who has not signed in opens Settings on the phone
- **THEN** the Security section shows "Sign in to use app lock" and no "App lock" switch

### Requirement: One PIN per account, set once
The app lock SHALL be off by default for an account. To turn it on, the user MUST set a PIN of either 4 or 6 digits and enter it a second time to confirm it. The PIN SHALL belong to the account, so that it is the same on every device where the user signs in. The system SHALL NOT turn the lock on if the two entries are different.

#### Scenario: Turn on the app lock
- **WHEN** the user turns on "App lock" on the phone, chooses a 6-digit PIN, and enters the same PIN again
- **THEN** the system saves the PIN to the account, turns the app lock on, and keeps the phone unlocked for the current use

#### Scenario: The other device gets the same PIN
- **WHEN** the user set the PIN on the phone and then opens the web app while signed in to the same account
- **THEN** the web app's lock is on, and the same PIN unlocks it

#### Scenario: Confirmation does not match
- **WHEN** the second PIN entry is different from the first
- **THEN** the system shows "PINs do not match", clears both entries, and the app lock stays off

#### Scenario: Cancel setup
- **WHEN** the user closes the set-PIN flow before confirmation
- **THEN** the app lock stays off and no PIN is stored

### Requirement: PIN changes need a connection
Setting, changing, and turning off the PIN SHALL write to the account first and change the local state only after the write succeeds. If the device is offline or the write fails, the system SHALL show "Connect to the internet to change your PIN" and SHALL NOT change the lock state.

#### Scenario: Offline PIN change
- **WHEN** the user tries to change the PIN while offline
- **THEN** the system shows the connection message and the old PIN still works on every device

### Requirement: PIN is never stored in plain text
The system SHALL store only a salted PBKDF2-HMAC-SHA256 hash of the PIN, with a random salt of at least 16 bytes and the iteration count beside it. This applies to the account copy and to each device copy. The system MUST NOT write the PIN itself to storage, the database, logs, or network payloads. On mobile, the device copy SHALL live in the platform keystore through `flutter_secure_storage`.

#### Scenario: No PIN anywhere
- **WHEN** the user sets the PIN 482916
- **THEN** no local value, database row, request body, or log line contains the string "482916", and the stored record holds a salt, an iteration count, a PIN length, and a hash

### Requirement: Unlock works offline
Each device SHALL keep a local copy of the account's PIN hash. The device SHALL check the PIN against the local copy, so that unlock works without a connection.

#### Scenario: Unlock in airplane mode
- **WHEN** the phone is offline and the user enters the correct PIN
- **THEN** the app unlocks

### Requirement: Devices follow PIN changes
When the account's PIN changes or the lock is turned off on one device, every other signed-in device SHALL update its local copy. Each device SHALL refresh on sign-in, on return to the foreground or tab show, and on a realtime change event for the `app_lock` row.

#### Scenario: PIN changed on the phone
- **WHEN** the user changes the PIN on the phone while the web app is open
- **THEN** after the web app receives the change, the new PIN unlocks it and the old PIN does not

#### Scenario: Lock turned off on the web
- **WHEN** the user turns off the app lock on the web
- **THEN** the phone's app lock is off after its next refresh

### Requirement: Locked app hides all content
While the app is locked, the system SHALL show an opaque lock screen above every route, dialog, and sheet. The lock screen MUST block all input to the content below it. Data and the signed-in session SHALL stay loaded, so that an unlock shows the same screen and state as before the lock.

#### Scenario: Lock over an open dialog
- **WHEN** the app locks while a transaction form dialog is open
- **THEN** the lock screen covers the dialog, and after unlock the dialog is still open with its entered values

#### Scenario: No content shows through
- **WHEN** the app is locked
- **THEN** no balance, transaction, or health value is visible or reachable by tap, click, keyboard focus, or screen reader

### Requirement: Unlock with PIN
The lock screen SHALL accept the PIN from an on-screen keypad. On web, it SHALL also accept the digit keys and Backspace from a physical keyboard. The system SHALL check the PIN as soon as the last digit is entered.

#### Scenario: Correct PIN
- **WHEN** the user enters the correct PIN
- **THEN** the lock screen closes and the app shows the screen it showed before the lock

#### Scenario: Wrong PIN
- **WHEN** the user enters a wrong PIN
- **THEN** the system clears the entry, shows "Wrong PIN" with a short shake (at most 300 ms), and stays locked

### Requirement: Biometric unlock on mobile with the PIN as backup
On mobile, if the device has an enrolled biometric, the system SHALL offer a "Use biometrics" setting for that device. When that setting is on, the lock screen SHALL start the biometric prompt first and automatically, and SHALL show a button to start it again. The PIN keypad SHALL always stay available as the backup. A failed or cancelled biometric attempt SHALL NOT count toward the wrong-PIN throttle. The web app SHALL NOT show any biometric option.

#### Scenario: Unlock with fingerprint
- **WHEN** the app locks on a phone with "Use biometrics" on, and the user passes the fingerprint prompt
- **THEN** the lock screen closes without a PIN

#### Scenario: Fall back to the PIN
- **WHEN** the user cancels the biometric prompt or it fails
- **THEN** the lock screen stays, and the correct PIN unlocks the app

#### Scenario: No enrolled biometric
- **WHEN** the device has no enrolled biometric
- **THEN** the "Use biometrics" setting is not shown

### Requirement: Auto-lock on mobile after background time
On mobile, the system SHALL record the time the app leaves the foreground. When the app returns to the foreground, the system SHALL lock if the time away is equal to or more than the device's "Lock after" setting. The "Lock after" options SHALL be Immediately, 1 minute, 5 minutes, and 15 minutes, with a default of 1 minute. A cold start SHALL always lock when the app lock is on.

#### Scenario: Return before the timeout
- **WHEN** "Lock after" is 5 minutes and the user returns to the app after 2 minutes
- **THEN** the app is not locked

#### Scenario: Return after the timeout
- **WHEN** "Lock after" is 1 minute and the user returns to the app after 3 minutes
- **THEN** the lock screen shows

#### Scenario: Cold start
- **WHEN** the app lock is on and the app process starts with a saved session
- **THEN** the lock screen shows before any content

### Requirement: Auto-lock on web after idle time
On web, the system SHALL treat pointer, wheel, touch, and keyboard input as activity. The system SHALL lock when no activity occurs for the device's "Lock after" setting, and time with the tab hidden SHALL count as idle time. The "Lock after" options SHALL be 1, 5, 15, 30, and 60 minutes, with a default of 5 minutes. The last activity time SHALL persist, so that a page reload locks if the idle time already passed.

#### Scenario: Idle in an open tab
- **WHEN** "Lock after" is 5 minutes and nobody touches the mouse or keyboard for 5 minutes
- **THEN** the lock screen shows

#### Scenario: Hidden tab
- **WHEN** the user switches to another tab for 20 minutes with "Lock after" at 15 minutes and then comes back
- **THEN** the lock screen shows

#### Scenario: Reload after the timeout
- **WHEN** the user reloads the page 10 minutes after the last activity with "Lock after" at 5 minutes
- **THEN** the lock screen shows before any content

#### Scenario: Reload during activity
- **WHEN** the user reloads the page 30 seconds after the last activity with "Lock after" at 5 minutes
- **THEN** the app is not locked

### Requirement: Per-device settings
"Lock after", "Use biometrics", the wrong-PIN count, the cooldown end time, and the last activity time SHALL be stored on each device and SHALL NOT sync. A change on one device SHALL NOT change another device.

#### Scenario: Different timeouts
- **WHEN** the user sets "Lock after" to Immediately on the phone
- **THEN** the web app's "Lock after" setting does not change

### Requirement: Manual lock
When the app lock is on, the system SHALL offer a "Lock now" action. On mobile it SHALL be in the Security section of Settings. On web it SHALL be on the More page and in the sidebar footer.

#### Scenario: Lock now
- **WHEN** the user selects "Lock now"
- **THEN** the lock screen shows at once

### Requirement: Wrong-PIN throttle
After 5 wrong PINs in a row on a device, the system SHALL block PIN entry on that device for a cooldown of 30 seconds. Each later wrong PIN SHALL double the cooldown, up to 15 minutes. A correct PIN or a biometric unlock SHALL reset the count. The count and the cooldown end time SHALL persist across restarts. On web, the 10th wrong PIN in a row SHALL sign the user out and start the Forgot PIN reset (see "Forgot PIN").

#### Scenario: Cooldown after 5 wrong PINs
- **WHEN** the user enters a wrong PIN 5 times in a row
- **THEN** the keypad is disabled and the lock screen shows a 30-second countdown

#### Scenario: Restart does not reset the throttle
- **WHEN** the app restarts during a cooldown
- **THEN** the cooldown continues from its stored end time

#### Scenario: Web sign-out after 10 wrong PINs
- **WHEN** the user enters a wrong PIN for the 10th time in a row on web
- **THEN** the system signs the user out and shows the login screen

### Requirement: Exempt in-app external activities
The system SHALL NOT lock because the app went to the background for an action the user started from inside the app. These actions are the photo picker, the camera, Google sign-in, opening a file, launching a URL, and the biometric prompt itself. The exemption SHALL end when that action returns.

#### Scenario: Pick a food photo
- **WHEN** "Lock after" is Immediately and the user opens the photo picker from the food log and picks a photo
- **THEN** the app returns to the food log without a lock

#### Scenario: Biometric prompt does not loop
- **WHEN** the biometric prompt pauses and resumes the app
- **THEN** the system does not start a new lock or a new biometric prompt

### Requirement: Fasting alarm is never covered
The lock screen SHALL NOT cover a live fasting alarm screen. If the lock is due while the alarm shows, the system SHALL show the lock screen after the user dismisses the alarm and returns to the app.

#### Scenario: Alarm on a locked app
- **WHEN** a fasting alarm fires while the app lock is engaged
- **THEN** the alarm screen shows and its actions work without a PIN

#### Scenario: After the alarm
- **WHEN** the user dismisses the alarm and opens the app
- **THEN** the lock screen shows

### Requirement: App-switcher privacy on Android
While the app lock is on, the system SHALL hide the app preview in the Android recent-apps screen on Android 13 (API 33) and later. The system SHALL NOT block screenshots. When the app lock is off, the system SHALL restore the normal preview.

#### Scenario: Recent apps
- **WHEN** the app lock is on and the user opens the recent-apps screen on Android 14
- **THEN** the app's card shows no app content

### Requirement: Forgot PIN
The lock screen SHALL show a "Forgot PIN?" action.
- On mobile, it SHALL ask for the device screen lock (PIN, pattern, password, or biometric). On success, it SHALL unlock the app and start a set-PIN flow that replaces the account PIN. If the device has no screen lock, the system SHALL tell the user to use Forgot PIN on the web.
- On web, it SHALL confirm, sign the user out, and mark a PIN reset as pending on that device. After the next sign-in on that device, the system SHALL require the user to set a new account PIN or turn the lock off before any content shows.

#### Scenario: Forgot PIN on mobile
- **WHEN** the user taps "Forgot PIN?" and passes the device screen lock
- **THEN** the app unlocks and asks for a new PIN, and the new PIN replaces the account PIN on all devices

#### Scenario: Forgot PIN on web
- **WHEN** the user clicks "Forgot PIN?", confirms, and signs in again with Google
- **THEN** the system shows the set-PIN flow before any content, and the new PIN replaces the account PIN on all devices

### Requirement: Turning off or changing the lock needs the current PIN
To turn the app lock off or to change the PIN, the user MUST enter the current PIN. The device's "Lock after" and "Use biometrics" settings SHALL change without the PIN, because the app is already unlocked.

#### Scenario: Turn off the lock
- **WHEN** the user turns off "App lock" and enters the correct current PIN
- **THEN** the system deletes the account PIN and turns the app lock off on all devices

#### Scenario: Wrong PIN while turning off
- **WHEN** the user enters a wrong current PIN
- **THEN** the app lock stays on and the attempt counts toward the wrong-PIN throttle

### Requirement: Sign-in and sign-out behavior
On sign-in, the system SHALL fetch the account's PIN hash. If the account has a PIN, the lock SHALL be on, and the device SHALL start unlocked, because the sign-in already proved the user's identity. On sign-out, the system SHALL delete the device's local copy of the PIN hash and the device's wrong-PIN state. The account PIN SHALL stay on the account.

#### Scenario: Sign out and sign in again
- **WHEN** a user with the app lock on signs out and later signs in again on the same laptop
- **THEN** the lock is on with the same PIN, and the app is unlocked for this use

#### Scenario: Another account on the same laptop
- **WHEN** a second person signs in with an account that has no PIN
- **THEN** that person sees no lock, and the first user's PIN is not stored on the laptop

### Requirement: Lock screen accessibility and layout
The keypad keys SHALL be at least 64 by 64 logical pixels, and the keypad SHALL sit in the bottom part of the screen on mobile. Every key and action SHALL have a screen-reader label. The PIN dots SHALL announce the number of digits entered and SHALL NOT announce the digits. The lock screen SHALL use theme colors and work in dark and light mode.

#### Scenario: Screen reader
- **WHEN** a screen-reader user enters 3 digits of a 6-digit PIN
- **THEN** the reader announces "3 of 6 digits entered" and does not read the digits
