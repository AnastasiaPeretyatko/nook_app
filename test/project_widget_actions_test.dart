import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:todo_app/home_widget/providers.dart';
import 'package:todo_app/home_widget/widget_actions.dart';

void main() {
  test(
    'recognises project widget routes without confusing existing widget taps',
    () {
      expect(
        widgetTapActionOf(Uri.parse('nook://widget/project?project=home')),
        WidgetTapAction.project,
      );
      expect(
        widgetTapActionOf(Uri.parse('nook://widget/project-task?task=42')),
        WidgetTapAction.projectTask,
      );
      expect(
        widgetTapActionOf(
          Uri.parse('nook://widget/project-toggle?task=42&day=2026-08-27'),
        ),
        WidgetTapAction.projectToggle,
      );
      expect(
        widgetTapActionOf(Uri.parse('nook://widget/open')),
        WidgetTapAction.open,
      );
    },
  );

  test('delivers the selected project and task to the running app', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(widgetTapProvider.notifier);

    notifier.reportUri(Uri.parse('nook://widget/project?project=home'));
    final project = container.read(widgetTapProvider);
    expect(project?.action, WidgetTapAction.project);
    expect(project?.projectId, 'home');

    notifier.reportUri(Uri.parse('nook://widget/project-task?task=42'));
    final task = container.read(widgetTapProvider);
    expect(task?.action, WidgetTapAction.projectTask);
    expect(task?.taskId, 42);
    expect(task?.serial, greaterThan(project!.serial));
  });
}
