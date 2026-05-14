UPDATE notification_templates
SET title = updates.title,
    body = updates.body,
    destination = updates.destination,
    updated_at = NOW()
FROM (
  VALUES
    ('meal.breakfast', 'meal', 'Breakfast cameo 🍳', 'Tiny breakfast check: say it, type it, or snap it before the coffee brain takes over ☕️', 'voice'),
    ('meal.lunch', 'meal', 'Lunch roll call 🥗', 'What did lunch look like? A quick voice note totally counts.', 'voice'),
    ('meal.dinner', 'meal', 'Dinner plot twist 🍽️', 'Future-you loves a complete log. Add dinner while it is still fresh ✨', 'voice'),
    ('engagement.end_of_day', 'engagement', 'Still time for a tiny save 🌙', 'One sentence beats a blank day. Drop in the meal you remember and call it a win.', 'voice'),
    ('engagement.reactivation_24h', 'engagement', 'Tiny check-in? 👋', 'A rough log is still useful. Coffee, oats, dal rice — give Amy a breadcrumb.', 'voice'),
    ('engagement.reactivation_48h', 'engagement', 'No judgment. Tiny reset? 🐾', 'Two quiet days happen. Log the last meal you remember and keep the rhythm alive-ish.', 'voice'),
    ('discovery.logging_modes', 'discovery', 'Try the lazy log lane 📸', 'Voice, text, or camera — pick the least annoying one and let Amy do the math.', 'camera'),
    ('engagement.calorie_halfway', 'engagement', 'Halfway there-ish 🔥', 'You are around the midpoint for today. Nice moment to make the next meal intentional.', 'home'),
    ('engagement.calorie_over_target', 'engagement', 'A little over today 👀', 'No panic. Quick check portions, snacks, and drinks so the log stays honest.', 'home')
) AS updates(template_key, kind, title, body, destination)
WHERE notification_templates.template_key = updates.template_key;
