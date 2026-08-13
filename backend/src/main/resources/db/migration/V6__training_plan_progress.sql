ALTER TABLE training_plan
    ADD COLUMN completed_days_json LONGTEXT NULL AFTER plan_json;

UPDATE training_plan
SET completed_days_json = '[]'
WHERE completed_days_json IS NULL;

ALTER TABLE training_plan
    MODIFY COLUMN completed_days_json LONGTEXT NOT NULL;
