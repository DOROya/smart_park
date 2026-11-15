import '../services/parking_pricing.dart'
    show kBaseStayHours, kDefaultGraceMinutes, kGracePeriodOptions;
import '../services/platform_fees.dart' show kPlatformFeeRate;

/// SmartPark's Terms and Conditions and Privacy Notice, one set per role.
/// Shown at sign-up, where the user must agree, and again from the Profile.
/// Figures come from the same constants the app runs on, so the terms can't
/// drift from what the app does.

/// Changes whenever the terms do; saved on the user's profile with the date
/// they agreed (`termsVersion`, `termsAcceptedAt`). Anyone whose saved version
/// differs is asked to accept the current terms when they open the app (see
/// terms_update_gate.dart), so bump this with every change to the text.
const String kTermsVersion = '2026-11-15';

const String kTermsUpdatedLabel = 'November 15, 2026';

const String kSupportEmail = 'smartpark.noreply@gmail.com';

/// Who runs SmartPark, as the terms name them.
const String kOperatorName = 'the SmartPark project team';

const String kDriverRole = 'Driver';
const String kParkingOwnerRole = 'Parking Owner';
const String kStaffRole = 'staff';

/// Days an owner has to settle a refund balance once SmartPark asks for it.
const int kRefundBalanceDueDays = 15;

/// Upheld warnings within a year after which an account may be suspended.
const int kWarningsBeforeSuspension = 3;

class TermsSection {
  const TermsSection(this.title, this.points);

  final String title;
  final List<String> points;
}

/// The sections for [role] ("Driver", "Parking Owner" or "staff"), numbered
/// in order; empty for any other role.
List<TermsSection> termsFor(String role) {
  final List<TermsSection> sections = switch (role) {
    kDriverRole => <TermsSection>[
      _about,
      _account(owner: false),
      ..._driverSections,
      _payments(owner: false),
      _conduct(owner: false),
      _privacy(_Reader.driver),
      _liability(_Reader.driver),
      ..._closing,
    ],
    kParkingOwnerRole => <TermsSection>[
      _about,
      _account(owner: true),
      ..._ownerSections,
      _payments(owner: true),
      _conduct(owner: true),
      _privacy(_Reader.owner),
      _liability(_Reader.owner),
      ..._closing,
    ],
    _ when role.trim().toLowerCase() == kStaffRole => <TermsSection>[
      _about,
      ..._staffSections,
      _privacy(_Reader.staff),
      _liability(_Reader.staff),
      ..._closing,
    ],
    _ => const <TermsSection>[],
  };
  return <TermsSection>[
    for (int i = 0; i < sections.length; i++)
      TermsSection('${i + 1}. ${sections[i].title}', sections[i].points),
  ];
}

enum _Reader { driver, owner, staff }

final String _commission = '${(kPlatformFeeRate * 100).round()}%';
final String _graceChoices = kGracePeriodOptions
    .where((int m) => m > 0)
    .join(', ');

const TermsSection _about = TermsSection('About SmartPark', <String>[
  'SmartPark is a mobile platform that lets drivers find private parking '
      'facilities, pay for parking in the app, and enter and exit with a QR '
      'ticket. Each facility is run by its own parking owner; SmartPark does '
      'not own or operate the facilities.',
  'SmartPark is operated by $kOperatorName as an academic Capstone project. '
      'You can reach the team at $kSupportEmail.',
  'SmartPark is not a reservation service. Buying a ticket does not hold a '
      'slot for you, and the slot counts shown in the app are for '
      'information only.',
  'By creating or using an account you agree to these Terms and Conditions '
      'and to the Privacy Notice below. If you do not agree, do not use '
      'SmartPark.',
]);

TermsSection _account({required bool owner}) =>
    TermsSection('Your Account', <String>[
      'You must be at least 18 years old to have an account.',
      'Give your real name and an email address you can use. You must verify '
          'the email before you can sign in.',
      'Keep your password to yourself. You are responsible for everything '
          'done with your account.',
      'Each account has one role, chosen at sign-up, and it cannot be changed '
          'later.',
      owner
          ? 'You can delete your account from your Profile once your facility '
                'has no vehicles inside, no tickets with unused hours and no '
                'refund balance left to pay. Your facility is then removed '
                'from SmartPark.'
          : 'You can delete your account from your Profile at any time while '
                'you are not parked. Unused hours on your tickets are given '
                'up and are not refunded.',
      'Deleting an account removes your name, email and sign-in. Payment, '
          'ticket and gate records are kept without your name for as long as '
          'the Privacy Notice says.',
    ]);

final List<TermsSection> _driverSections = <TermsSection>[
  TermsSection('Tickets', <String>[
    'A ticket buys parking time at one facility for one vehicle type (car, '
        'motorcycle, or another type the facility accepts, such as a truck). '
        'The vehicle type cannot be changed after purchase.',
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
  const TermsSection('At the Gate', <String>[
    'Show your ticket\'s QR code to the gate staff on entry and exit. If the '
        'code cannot be read, the staff can find your ticket by its plate.',
    'Gate staff will refuse entry if the vehicle is not the type the ticket '
        'was bought for, if the ticket has no hours left or is already '
        'inside, or if SmartPark has suspended or deactivated the facility. '
        'Vehicles already inside can always exit.',
    'Every entry and exit is recorded with the time, the plate and the staff '
        'member who scanned it.',
  ]),
  TermsSection('Overtime', <String>[
    'If you stay longer than the time left on your ticket, the facility may '
        'charge overtime at its posted overtime rate.',
    'The overtime rate for a ticket is the one posted when you made its '
        'temporary QR, the same moment its price was fixed. If the facility '
        'changes its rate later, your ticket keeps the old one.',
    'Each facility sets a grace period after your paid time ($kDefaultGraceMinutes '
        'minutes unless the owner picked another). Leave within it and you '
        'pay no overtime. Past it, every started hour after your paid time '
        'counts as one overtime hour.',
    'Overtime is paid in cash to the gate staff at the exit. It is not paid '
        'through the app. The app shows how the charge was worked out, and '
        'you may ask the facility for its own receipt.',
  ]),
];

final List<TermsSection> _ownerSections = <TermsSection>[
  const TermsSection('Registering a Facility', <String>[
    'Give true and complete details about your facility: its name, '
        'location, operating hours, rates, slot counts and policies.',
    'Upload valid business documents, such as a business permit, a DTI or '
        'SEC registration, or a BIR certificate, and give the date your '
        'business permit expires. A SmartPark administrator reviews every '
        'facility before drivers can see it, and may reject it with a '
        'reason.',
    'Keep your permit current. Upload the renewed permit and its new expiry '
        'date before the old one lapses. A permit that expires after your '
        'facility was approved is your responsibility, not SmartPark\'s.',
    'Changing your business documents sends the facility back for review.',
  ]),
  TermsSection('Rates and Gate Rules', <String>[
    'You set your own rates, packages, operating hours, policies and '
        'overtime grace period (none, or $_graceChoices minutes; '
        '$kDefaultGraceMinutes minutes if you do not pick one). Keep them '
        'accurate: drivers see them before they buy.',
    'Honour every valid ticket. Charge overtime only as the app shows it, '
        'collect it in cash at the exit, and confirm it in the app. A ticket '
        'keeps the overtime rate that was posted when its price was fixed.',
    'Do not admit vehicles while SmartPark has your facility suspended or '
        'deactivated. Vehicles already inside must still be let out.',
    'You are the seller of the parking. Issuing official receipts or '
        'invoices to drivers, including for overtime cash, and paying the '
        'taxes on your sales are your responsibility. SmartPark\'s in-app '
        'receipts and reports are records only.',
    'Your staff record the plates of walk-in customers who do not use '
        'SmartPark. Post a notice at your gate telling them so.',
  ]),
  const TermsSection('Staff Accounts', <String>[
    'You create and manage your gate staff\'s accounts. You are responsible '
        'for what your staff do in SmartPark.',
    'Deactivate a staff account as soon as that person no longer works for '
        'you.',
    'Staff may flag a driver to you. You decide whether to report it to '
        'SmartPark or dismiss it.',
  ]),
];

const List<TermsSection> _staffSections = <TermsSection>[
  TermsSection('Your Staff Account', <String>[
    'Your account was made by the parking owner you work for, who can reset '
        'its password and deactivate it. It works only at that owner\'s '
        'facility.',
    'Keep your password to yourself. Every scan and every overtime payment '
        'you confirm is recorded under your name.',
    'To have your account removed, ask your parking owner.',
  ]),
  TermsSection('Working the Gate', <String>[
    'Scan every vehicle in and out, and admit only vehicles the app allows. '
        'Do not admit vehicles while the facility is suspended or '
        'deactivated; vehicles already inside must still be let out.',
    'Start a payment on a temporary QR only after you have checked there is '
        'space for the vehicle.',
    'Charge overtime only as the app shows it, collect it in cash, and mark '
        'it collected only when you have received it.',
    'Flag a driver to your parking owner only for things that really '
        'happened.',
    'Use the names, plates and tickets you see only to do your job. Do not '
        'copy, share or sell them.',
  ]),
];

TermsSection _payments({required bool owner}) => TermsSection(
  'Payments and Refunds',
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
          'If SmartPark suspends or deactivates your facility, drivers are '
              'refunded the unused hours on their tickets. You cover these '
              'refunds, including PayMongo\'s fee, unless the reason was '
              'documents SmartPark approved (a business permit that was '
              'already invalid when approved, or incomplete or false '
              'documents), in which case SmartPark covers them. SmartPark '
              'gives back its own commission on every refunded amount, so '
              'you never repay that part.',
          'What you owe is taken from up to half of your share of each later '
              'online sale, and every refund is listed in your Report tab. '
              'You are notified of each refund charged to you.',
          'If you think a refund should not be charged to you, dispute it '
              'from the refund in your Report tab. A SmartPark administrator '
              'reviews it and, if you are right, moves the charge to '
              'SmartPark.',
          'If your facility is deactivated, or makes no online sale for 30 '
              'days, SmartPark may ask you in writing to pay the balance '
              'directly. It is then due within $kRefundBalanceDueDays days. '
              'SmartPark may decline to reinstate a facility or approve a '
              'new one while a balance is unpaid.',
        ]
      : <String>[
          'Payments are made through PayMongo (card, GCash, Maya or QR Ph). '
              'SmartPark never sees or stores card details.',
          'You are not charged when you pick a package. The app gives you a '
              'temporary QR, valid for 3 days. You pay only at the gate, on '
              'your own phone, after staff confirm there is space. If there '
              'is no space, nothing is charged.',
          'Paying at the gate needs mobile data. Temporary QRs cannot be '
              'paid in cash; without data, you may park as a regular walk-in '
              "under the facility's own terms.",
          'The price is set by the facility and shown when you make the '
              'temporary QR, and that price is kept until it expires. A '
              'ticket is issued only once PayMongo confirms the payment.',
          'The facility is the seller of the parking. The receipt in the app '
              'is SmartPark\'s record of your payment, not an official '
              'receipt; ask the facility if you need one.',
          'Unused hours stay on a paid ticket for later visits. Paid tickets '
              'are not refunded because you change your mind.',
          'If SmartPark deactivates a facility, the unused hours on your '
              'tickets for it are refunded automatically, in full, to the '
              'account you paid with. If you are parked there at the time, '
              'the hours left after you exit are refunded.',
          'If SmartPark suspends a facility, its tickets cannot be used to '
              'enter until it is reinstated, and their hours are kept. If it '
              'is still suspended after 14 days, the unused hours are '
              'refunded automatically. You may also request the refund '
              'sooner; a SmartPark administrator reviews these requests. A '
              'request not yet decided when the facility is reinstated is '
              'closed, because the ticket can be used again.',
          'You are notified when a refund is sent, and if one is declined or '
              'fails. Refunds go through PayMongo and can take several days '
              'to appear, depending on how you paid. If one does not arrive, '
              'contact SmartPark at $kSupportEmail.',
          'If you were charged but no ticket appeared, or you think a charge '
              'is wrong, contact SmartPark at $kSupportEmail.',
        ],
);

TermsSection _conduct({required bool owner}) => TermsSection(
  'Conduct, Reports and Suspension',
  owner
      ? <String>[
          'You may report a driver to SmartPark from their ticket. Reports '
              'must be true and choose the reasons that apply. The driver is '
              'not told who reported them.',
          'Drivers may report your facility to SmartPark from their tickets. '
              'A SmartPark administrator reviews every report.',
          'A SmartPark administrator may suspend or deactivate your facility, '
              'for example for invalid, expired or false documents, safety '
              'concerns, rates that differ from the listing, repeated driver '
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
              'If you disagree with a warning, contest it there; an '
              'administrator reviews it and may withdraw it.',
          'SmartPark may suspend or close an account for fraud, a fake '
              'ticket, or $kWarningsBeforeSuspension or more upheld warnings '
              'within 12 months. You are told the reason and may ask for a '
              'review at $kSupportEmail.',
          'You may report a facility to SmartPark from any of your tickets '
              'for it, for example for refusing a valid ticket, charging '
              'more than the app shows, being closed during its posted '
              'hours, or unsafe conditions. The facility is not told who '
              'reported it.',
        ],
);

TermsSection _privacy(_Reader reader) =>
    TermsSection('Privacy Notice', <String>[
      'SmartPark follows the Data Privacy Act of 2012 (Republic Act No. '
          '10173). Your information is handled by $kOperatorName, who answer '
          'privacy questions at $kSupportEmail.',
      switch (reader) {
        _Reader.owner =>
          'We collect your name, email address, facility details and '
              'location, business documents and permit expiry date, rates '
              'and settings, your staff accounts, and the tickets, payments, '
              'gate scans, refunds, reports and flags at your facility.',
        _Reader.driver =>
          'We collect your name, email address, the vehicle plates and types '
              'on your tickets, your tickets and payment records (amount, '
              'method and status), your gate entries and exits, your refunds, '
              'and any reports and warnings about you or made by you. Your '
              'phone\'s location is used only on your device to show parking '
              'near you; it is not stored.',
        _Reader.staff =>
          'We collect the name and username your parking owner gave you, and '
              'a record of every scan, walk-in, overtime payment and flag '
              'you make at the gate.',
      },
      if (reader != _Reader.staff)
        'If you allow notifications, we keep an identifier for each phone '
            'you sign in on so notices reach it. It is removed when you sign '
            'out.',
      if (reader == _Reader.owner)
        'Your staff record the plates of walk-in customers who do not have '
            'a SmartPark account. Those plates are used only to count '
            'occupancy and show gate activity.',
      'If the app crashes, a crash report with your phone model, system '
          'version and account identifier is sent to us so we can fix it.',
      'We use this information only to run SmartPark: to issue and check '
          'tickets, record payments, refunds and overtime, show activity to '
          'the people who need it, and handle reports.',
      switch (reader) {
        _Reader.owner =>
          'Your facility\'s public details (name, address, rates, hours, '
              'policies and photos) are shown to drivers. Business documents '
              'are seen only by you and SmartPark administrators.',
        _Reader.driver =>
          'The owner and gate staff of a facility can see your name, plate '
              'and tickets for that facility, but not your email address. '
              'SmartPark administrators can see all records. When you pay, '
              'your name and email address are passed to PayMongo to fill in '
              'the payment page; PayMongo handles the payment under its own '
              'privacy policy.',
        _Reader.staff =>
          'Your parking owner and SmartPark administrators can see your name '
              'and your gate activity.',
      },
      if (reader == _Reader.owner)
        'Use the drivers\' information you see only to run your facility. Do '
            'not copy, share or sell it.',
      'SmartPark runs on Google Firebase, with Google Maps for the map and '
          'PayMongo for payments. Your information is stored on Google '
          'servers outside the Philippines, in Singapore and the United '
          'States.',
      'Account details are kept while your account is active and removed '
          'when it is deleted. Payment, ticket, refund and gate records are '
          'kept for 5 years for payment and dispute purposes, without your '
          'name once your account is deleted. Reports and warnings are kept '
          'for 2 years. Unused temporary QRs are deleted when they expire.',
      'You may ask to see, correct or delete your personal information, or '
          'withdraw consent, by emailing $kSupportEmail. Some records, such '
          'as payments, may have to be kept.',
      'If you are not satisfied with how we handle a privacy concern, you '
          'may complain to the National Privacy Commission.',
    ]);

TermsSection _liability(_Reader reader) =>
    TermsSection('Responsibility and Liability', <String>[
      switch (reader) {
        _Reader.driver =>
          'Parking is provided by the facility\'s owner, not by SmartPark. '
              'The owner and its staff are in charge of the premises and of '
              'vehicles parked there. Claims for loss of or damage to a '
              'vehicle or its contents are made to the facility\'s owner.',
        _Reader.owner =>
          'You provide the parking and are in charge of your premises and '
              'of the vehicles parked there. Claims for loss of or damage '
              'to a vehicle or its contents are yours to answer, and you '
              'will cover SmartPark for any such claim made against it.',
        _Reader.staff =>
          'You act for the parking owner you work for. The owner is in '
              'charge of the premises and of the vehicles parked there.',
      },
      'SmartPark is responsible for what it does itself: showing each '
          'facility\'s listing as the owner gave it, processing payments and '
          'refunds through PayMongo, and keeping gate records. SmartPark '
          'checks each owner\'s business documents before listing a '
          'facility, but does not guarantee a facility\'s safety, '
          'availability or service.',
      'The app may sometimes be unavailable, for example without mobile '
          'data or during maintenance. SmartPark is not liable for losses '
          'caused by that, except where the law does not allow this limit.',
      'Nothing in these terms takes away rights you have under Philippine '
          'consumer law.',
    ]);

const List<TermsSection> _closing = <TermsSection>[
  TermsSection('Changes to These Terms', <String>[
    'SmartPark may update these terms. The date at the top shows the latest '
        'version, and you can read the current terms anytime from your '
        'Profile.',
    'When the terms change, the app shows you the new version the next time '
        'you open it and asks you to accept it before you continue. If you '
        'do not accept, you can sign out and ask us by email to delete your '
        'account.',
  ]),
  TermsSection('Disputes and Governing Law', <String>[
    'These terms are governed by the laws of the Republic of the '
        'Philippines.',
    'Tell us about a problem first at $kSupportEmail; we answer within 7 '
        'days and try to settle it with you. A dispute that is not settled '
        'this way may be brought to the Department of Trade and Industry, '
        'the National Privacy Commission for privacy matters, or the proper '
        'Philippine courts.',
  ]),
  TermsSection('Contact', <String>[
    'Questions, payment problems and privacy requests: $kSupportEmail.',
  ]),
];
