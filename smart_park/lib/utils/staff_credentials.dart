/// Firebase Auth's email/password provider requires an email-shaped
/// identifier, but staff sign in with a plain username instead of an email.
/// This is the fixed, fake domain used to turn a staff username into a
/// valid Firebase Auth email under the hood; it never needs to resolve or
/// receive mail, and staff never see it.
const String kStaffAuthEmailDomain = 'staff.smartpark.internal';

String staffUsernameToAuthEmail(String username) =>
    '${username.trim().toLowerCase()}@$kStaffAuthEmailDomain';

bool isStaffAuthEmail(String? email) =>
    (email ?? '').trim().toLowerCase().endsWith('@$kStaffAuthEmailDomain');
