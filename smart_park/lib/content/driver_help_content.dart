/// Words for the driver's first-run guide and Help & FAQ screen. Numbers
/// come from the same constants the app and terms use, so the help never
/// says something the app doesn't do.
library;

import 'package:flutter/material.dart';

import '../services/parking_pricing.dart'
    show kBaseStayHours, kDefaultGraceMinutes, kTurnaroundMinutes;
import 'terms_content.dart' show kSupportEmail;

/// Days a temporary QR stays usable. Must match PASS_LIFETIME_MS in
/// functions/src/gate_pass.js.
const int kTemporaryQrValidDays = 3;

/// One page of the first-run guide.
class DriverGuideStep {
  const DriverGuideStep({
    required this.icon,
    required this.title,
    required this.body,
    required this.points,
  });

  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
}

/// How SmartPark works, in the order a driver meets it.
const List<DriverGuideStep> kDriverGuideSteps = <DriverGuideStep>[
  DriverGuideStep(
    icon: Icons.map_rounded,
    title: 'Find parking',
    body: 'The map and list show approved parking near you.',
    points: <String>[
      'Sort by nearest, cheapest, top rated or most slots.',
      'Filter by vehicle type or open now.',
      'Tap the heart to save a place you use often.',
    ],
  ),
  DriverGuideStep(
    icon: Icons.qr_code_2_rounded,
    title: 'Get a temporary QR',
    body:
        'Pick your vehicle and how many hours you want. You are not charged yet.',
    points: <String>[
      'You get a temporary QR, valid for $kTemporaryQrValidDays days.',
      'The price is fixed when you make it, even if the facility changes its rates later.',
      'Add your GCash, Maya or card details now, so paying at the gate is one tap.',
    ],
  ),
  DriverGuideStep(
    icon: Icons.door_sliding_rounded,
    title: 'Pay at the gate',
    body: 'Show the temporary QR to the gate staff.',
    points: <String>[
      'Staff check there is space, then your phone asks you to pay.',
      'Tap Confirm and approve the payment. Only then are you charged.',
      'No space? Nothing is charged. Paying needs mobile data.',
    ],
  ),
  DriverGuideStep(
    icon: Icons.local_parking_rounded,
    title: 'Park with your ticket',
    body: 'Once paid, your ticket is in the Tickets tab.',
    points: <String>[
      'Show its QR when you enter and when you leave.',
      'Unused hours stay on the ticket for your next visit.',
      'Running out of time? Add hours in the app. Staying past your time is overtime, paid in cash at the exit.',
    ],
  ),
];

/// A question and its answer on the Help & FAQ screen.
class DriverFaq {
  const DriverFaq(this.question, this.answer);

  final String question;
  final String answer;
}

/// A group of questions under one heading.
class DriverFaqGroup {
  const DriverFaqGroup(this.title, this.icon, this.items);

  final String title;
  final IconData icon;
  final List<DriverFaq> items;
}

const List<DriverFaqGroup> kDriverFaqGroups = <DriverFaqGroup>[
  DriverFaqGroup('Paying', Icons.payments_outlined, <DriverFaq>[
    DriverFaq(
      'When am I charged?',
      'Only at the gate, when you tap Confirm and approve the payment. '
          'Making a temporary QR costs nothing. If the facility has no '
          'space, nothing is charged.',
    ),
    DriverFaq(
      'My temporary QR expired.',
      'A temporary QR lasts $kTemporaryQrValidDays days and was never '
          'charged, so nothing is lost. Open the facility again and make a '
          'new one. Its price will be the facility\'s current price.',
    ),
    DriverFaq(
      'I was charged but no ticket appeared.',
      'A ticket appears once PayMongo confirms your payment. This usually '
          'takes seconds. SmartPark also checks unconfirmed payments again '
          'every 15 minutes, so a ticket can arrive a little later even if '
          'the app was closed. If there is still no ticket after an hour, '
          'email $kSupportEmail with the time, amount and facility.',
    ),
    DriverFaq(
      'I paid but the gate did not let me in.',
      'Show the staff your ticket in the Tickets tab. If the QR does not '
          'scan, they can find it by your plate. If the ticket is missing, '
          'see the answer above.',
    ),
    DriverFaq(
      'Can I pay in cash or without mobile data?',
      'A temporary QR can only be paid in the app, which needs mobile data. '
          'Without data you can still park as a regular walk-in under the '
          'facility\'s own terms. Overtime is the one charge always paid in '
          'cash, at the exit.',
    ),
  ]),
  DriverFaqGroup(
    'Tickets and time',
    Icons.confirmation_number_outlined,
    <DriverFaq>[
      DriverFaq(
        'Can I use my ticket again?',
        'Yes. Hours are only used while you are parked, and the rest stay on '
            'the ticket for later visits. Each visit uses at least '
            '$kBaseStayHours hours. If you leave within $kTurnaroundMinutes '
            'minutes, for example because you found no space, that visit '
            'uses no hours.',
      ),
      DriverFaq(
        'What is overtime?',
        'Staying longer than the time left on your ticket. Each facility '
            'gives a grace period ($kDefaultGraceMinutes minutes unless the '
            'owner picked another). Past it, every started hour is charged at '
            'the overtime rate fixed when you bought the ticket, paid in cash '
            'at the exit. To avoid it, add hours in the app before your time '
            'runs out. SmartPark sends a reminder.',
      ),
      DriverFaq(
        'Can someone else use my ticket, or can I change the plate?',
        'A ticket is for one vehicle type, not one plate. You can share it or '
            'change its plate while the vehicle is not parked. The vehicle '
            'type cannot be changed, and only one vehicle can be inside on a '
            'ticket at a time.',
      ),
      DriverFaq(
        'Does buying a ticket save me a slot?',
        'No. SmartPark is not a reservation service. Slot counts are for '
            'information; staff confirm space at the gate before you pay.',
      ),
    ],
  ),
  DriverFaqGroup(
    'Refunds and problems',
    Icons.support_agent_rounded,
    <DriverFaq>[
      DriverFaq(
        'Can I get a refund?',
        'Paid tickets are not refunded for a change of mind. If SmartPark '
            'deactivates a facility, its unused hours are refunded '
            'automatically. If it suspends one, you can tap Request refund on '
            'the ticket, and unused hours are refunded automatically if it is '
            'still suspended after 14 days. A refund is not the full price: '
            'SmartPark\'s fee and PayMongo\'s processing fee are kept back, '
            'and the ticket shows the calculation.',
      ),
      DriverFaq(
        'How do I report a facility?',
        'Open the ticket you used there in the Tickets tab and tap Report '
            'facility. '
            'A SmartPark administrator reviews every report. The facility is '
            'not told who reported it.',
      ),
      DriverFaq(
        'How do I get a copy of my data or delete my account?',
        'Both are at the bottom of your Profile: Download My Data saves a copy '
            'of everything SmartPark keeps about you, and Delete Account '
            'removes your name, email and sign-in.',
      ),
    ],
  ),
];
