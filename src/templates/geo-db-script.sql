-- geo-cli SQL script template
-------------------------------------------------------------------------------
-- Add parameters with default values. 
-- You can include values for these parameters at the command line like so:
--   geo db script <script_name> --param1 'value1' --param2 'value2'
-- Note: parameter definition must start with 3 dashes '---'
--
-- Parameter Definition:
--- desc_text=some text
--- hardware_id=123
-------------------------------------------------------------------------------

-- Example script:

SELECT * FROM vehicle
WHERE sdescription LIKE '{{desc_text}}' 
OR ihardwareid = {{hardware_id}};