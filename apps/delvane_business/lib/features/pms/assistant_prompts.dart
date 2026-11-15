import '../../core/localization/web_strings.dart';

/// Stable suggestion identity; localize once for both display and user text.
enum AssistantPrompt {
  concerns('Anything concerning tomorrow?'),
  registration('Who still needs registration?'),
  readiness("Which properties aren't ready?"),
  cancellations('How many reservations were cancelled?'),
  demoArrivals('Summarize demo arrivals'),
  demoTasks('What tasks are open?');

  const AssistantPrompt(this.english);
  final String english;
  String text(WebStrings strings) => strings.t(english);
}

const ownerAssistantPrompts = [
  AssistantPrompt.concerns,
  AssistantPrompt.registration,
  AssistantPrompt.readiness,
  AssistantPrompt.cancellations,
];
