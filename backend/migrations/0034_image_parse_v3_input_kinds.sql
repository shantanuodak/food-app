ALTER TABLE food_logs
  DROP CONSTRAINT IF EXISTS food_logs_input_kind_check;

ALTER TABLE food_logs
  ADD CONSTRAINT food_logs_input_kind_check
  CHECK (input_kind IN ('text', 'image', 'image_barcode', 'image_label', 'voice', 'manual'));
