import '../services/parking_pricing.dart'
    show kBaseStayHours, kDefaultGraceMinutes, kGracePeriodOptions;
import '../services/platform_fees.dart' show kPlatformFeeRate;

/// SmartPark's Terms and Conditions and Privacy Notice, one set per role.
/// Shown at sign-up, where the user must agree, and again from the Profile.
/// Figures come from the same constants the app runs on, so the terms can't
/// drift from what the app does.

/// Changes whenever the terms do; saved on the user's profile with the date
/// they agreed (`termsVersion`, `termsAcceptedAt`).
const String kTermsVersion = '2026-11-03';

const String kTermsUpdatedLabel = 'November 3, 2026';

const String kSupportEmail = 'smartpark.noreply@gmail.com';

const String kDriverRole = 'Driver';
const String kParkingOwnerRole = 'Parking Owner';

class TermsSection {
  const TermsSection(this.title, this.points);

  final String title;
  final List<String> points;
}

/// The sections for [role] ("Driver" or "Parking Owner"); empty for any
/// other role.
List<TermsSection> termsFor(String role) => switch (role) {
  kDriverRole => <TermsSection>[
    _about,
    _account,
    ..._driverSections,
    _payments(owner: false),
    _conduct(owner: false),
    _privacy(owner: false),
    ..._closing,
  ],
  kParkingOwnerRole => <TermsSection>[
    _about,
    _account,
    ..._ownerSections,
    _payments(owner: true),
    _conduct(owner: true),
    _privacy(owner: true),
    ..._closing,
  ],
  _ => const <TermsSection>[],
};

final String _commission = '${(kPlatformFeeRate * 100).round()}%';
final String _graceChoices = kGracePeriodOptions
    .where((int m) => m > 0)
    .join(', ');

const TermsSection _about = TermsSection('1. About SmartPark', <String>[
  'SmartPark is a mobile platform that lets drivers find private parking '
      'facilities, pay for parking in the app, and enter and exit with a QR '
      'ticket. Each facility is run by its own parking owner; SmartPark does '
      'not own or operate the facilities.',
  'SmartPark is not a reservation service. Buying a ticket does not hold a '
      'slot for you, and the slot counts shown in the app are for '
      'information only.',
  'By creating an account you agree to these Terms and Conditions and to '
      'the Privacy Notice below. If you do not agree, do not create an '
      'account.',
]);

const TermsSection _account = TermsSection('2. Your Account', <String>[
  'Give your real name and an email address you can use. You must verify '
      'the email before you can sign in.',
  'Keep your password to yourself. You are responsible for everything done '
      'with your account.',
  'Each account has one role, chosen at sign-up, and it cannot be changed '
      'later.',
]);

final List<TermsSection> _driverSections = <TermsSection>[
  TermsSection('3. Tickets', <String>[
    'A ticket buys parking time at one facility for one vehicle type (car or '
        'motorcycle). The vehicle type cannot be changed after purchase.',
    'You may share a ticket with someone else, but only for the same vehicle '
        'type. The account that bought the ticket stays responsible for how '
        'it is used.',
    'A ticket can be reused on later visits until its hours run out. Hours '
        'are only used while the vehicle is parked, and each visit uses at '
        'least $kBaseStayHours hours. The time left is not an expiry date.',
    'You can change the plate on a ticket while the vehicle is not parked. '
        'Each gate scan records the plate actually used.',
    'Only one vehicle can be inside on a ticket at a time.',
  ]),
  TermsSection('4. At the Gate', <String>[
    'Show your ticket\'s QR code to the gate staff on entry and exit. If the '
        'code cannot be read, the staff can find your ticket by its plate.',
    'Gate staff will refuse entry if the vehicle is not the type the ticket '
        'was bought for, if the ticket has no hours left or is already '
        'inside, or if SmartPark has suspended or deactivated the facility. '
        'Vehicles already inside can always exit.',
    'Every entry and exit is recorded with the time, the plate and the staff '
        'member who scanned it.',
  ]),
  TermsSection('5. Overtime', <String>[
    'If you stay longer than the time left on your ticket, the facility may '
        'charge overtime at its posted overtime rate.',
    'Each facility sets a grace period after your paid time ($kDefaultGraceMinutes '
        'minutes unless the owner picked another). Leave within it and you '
        'pay no overtime. Past it, every started hour after your paid time '
        'counts as one overtime hour.',
    'Overtime is paid in cash to the gate staff at the exit. It is not paid '
        'through the app. The app shows how the charge was worked out.',
  ]),
];

final List<TermsSection> _ownerSections = <TermsSection>[
  const TermsSection('3. Registering a Facility', <String>[
    'Give true and complete details about your facility: its name, '
        'location, operating hours, rates, slot counts and policies.',
    'Upload valid business documents, such as a business permit, a DTI or '
        'SEC registration, or a BIR certificate. A SmartPark administrator '
        'reviews every facility before drivers can see it, and may reject it '
        'with a reason.',
    'Changing your business documents sends the facility back for review.',
  ]),
  TermsSection('4. Rates and Gate Rules', <String>[
    'You set your own rates, packages, operating hours, policies and '
        'overtime grace period (none, or $_graceChoices minutes; '
        '$kDefaultGraceMinutes minutes if you do not pick one). Keep them '
        'accurate: drivers see them before they buy.',
    'Honour every valid ticket. Charge overtime only as the app shows it, '
        'collect it in cash at the exit, and confirm it in the app.',
    'Do not admit vehicles while SmartPark has your facility suspended or '
        'deactivated. Vehicles already inside must still be let out.',
  ]),
  const TermsSection('5. Staff Accounts', <String>[
    'You create and manage your gate staff\'s accounts. You are responsible '
        'for what your staff do in SmartPark.',
    'Deactivate a staff account as soon as that person no longer works for '
        'you.',
    'Staff may flag a driver to you. You decide whether to report it to '
        'SmartPark or dismiss it.',
  ]),
];

TermsSection _payments({required bool owner}) => TermsSection(
  '6. Payments and Refunds',
  owner
      ? <String>[
          'Drivers pay through PayMongo (card, GCash, Maya or QR Ph). '
              'SmartPark never sees or stores card details.',
          'SmartPark keeps a $_commission platform commission from each '
              'ticket payment. PayMongo\'s processing fees are also deducted. '
              'The rest is paid out to you by PayMongo.',
          'Overtime cash is collected by your staff at the gate and is not '
              'part of these payouts.',
          'SmartPark records each payment and how it was split, so you can '
              'check your earnings in the app.',
        ]
      : <String>[
          'Payments are made through PayMongo (card, GCash, Maya or QR Ph). '
              'SmartPark never sees or stores card details.',
          'The price is set by the facility and shown before you pay. A '
              'ticket is issued only once PayMongo confirms the payment.',
          'Paid tickets cannot be cancelled or refunded in the app. Unused '
              'hours stay on the ticket for later visits. If SmartPark '
              'suspends a facility, its tickets cannot be used to enter until '
              'it is reinstated, and their hours are kept.',
          'If you were charged but no ticket appeared, or you think a charge '
              'is wrong, contact SmartPark at $kSupportEmail.',
        ],
);

TermsSection _conduct({required bool owner}) => TermsSection(
  '7. Conduct, Reports and Suspension',
  owner
      ? <String>[
          'You may report a driver to SmartPark from their ticket. Reports '
              'must be true and choose the reasons that apply. The driver is '
              'not told who reported them.',
          'A SmartPark administrator may suspend or deactivate your facility, '
              'for example for invalid or false documents, safety concerns, '
              'rates that differ from the listing, repeated driver '
              'complaints, a facility that is not operating, or a SmartPark '
              'policy violation. You are told the reasons and can ask for a '
              'review in the app.',
          'While a facility is suspended or deactivated, it is hidden from '
              'drivers and cannot sell tickets.',
        ]
      : <String>[
          'Follow each facility\'s rules and its staff\'s instructions, pay '
              'any overtime, and treat staff with respect.',
          'Parking owners may report a driver to SmartPark, for example for '
              'refusing to pay overtime, using a ticket for the wrong vehicle '
              'type, or using a fake ticket. A SmartPark administrator '
              'reviews every report.',
          'If a report is upheld you receive a warning, shown once when you '
              'open the app and kept under Account Notices in your Profile. '
              'Repeated warnings may lead to action on your account.',
        ],
);

TermsSection _privacy({
  required bool owner,
}) => TermsSection('8. Privacy Notice', <String>[
  'SmartPark follows the Data Privacy Act of 2012 (Republic Act No. 10173).',
  owner
      ? 'We collect your name, email address, facility details and '
            'location, business documents, rates and settings, your staff '
            'accounts, and the tickets, payments, gate scans, reports and '
            'flags at your facility.'
      : 'We collect your name, email address, the vehicle plates and types '
            'on your tickets, your tickets and payment records (amount, '
            'method and status), your gate entries and exits, and any '
            'reports and warnings about you. Your phone\'s location is used '
            'only on your device to show parking near you; it is not '
            'stored.',
  'We use this information only to run SmartPark: to issue and check '
      'tickets, record payments and overtime, show activity to the people '
      'who need it, and handle reports.',
  owner
      ? 'Your facility\'s public details (name, address, rates, hours, '
            'policies and photos) are shown to drivers. Business documents '
            'are seen only by you and SmartPark administrators.'
      : 'The owner and gate staff of a facility can see your name, plate '
            'and tickets for that facility. SmartPark administrators can see '
            'all records. Payments are handled by PayMongo under its own '
            'privacy policy.',
  if (owner)
    'Use the drivers\' information you see only to run your facility. Do '
        'not copy, share or sell it.',
  'Records are kept while your account is active and as long as needed for '
      'payment and dispute records.',
  'You may ask to see, correct or delete your personal information, or '
      'withdraw consent, by emailing $kSupportEmail. Some records, such as '
      'payments, may have to be kept.',
]);

const List<TermsSection> _closing = <TermsSection>[
  TermsSection('9. Changes to These Terms', <String>[
    'SmartPark may update these terms. The date at the top shows the latest '
        'version, and you can read the current terms anytime from your '
        'Profile. Continuing to use SmartPark after a change means you accept '
        'it.',
  ]),
  TermsSection('10. Contact', <String>[
    'Questions, payment problems and privacy requests: $kSupportEmail.',
  ]),
];
