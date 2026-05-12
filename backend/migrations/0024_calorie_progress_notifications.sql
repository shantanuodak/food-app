INSERT INTO notification_templates (template_key, kind, title, body, destination)
VALUES
  (
    'engagement.calorie_halfway',
    'engagement',
    'Halfway through today''s calories',
    'You are about halfway through today''s calorie target. Keep the next meal intentional so you do not drift past it.',
    'home'
  ),
  (
    'engagement.calorie_over_target',
    'engagement',
    'Over today''s calorie target',
    'You are over today''s calorie target. Double-check portions, snacks, and drinks so the log stays honest.',
    'home'
  )
ON CONFLICT (template_key) DO NOTHING;
