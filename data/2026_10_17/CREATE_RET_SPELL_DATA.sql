DROP VIEW IF EXISTS RET_SPELL_DATA;

CREATE VIEW RET_SPELL_DATA AS
SELECT 
    se.SpellID,
    sn.Name_lang AS SpellName,
    se.EffectBonusCoefficient,
    REPLACE(ROUND(se.EffectBonusCoefficient * 100, 1) || '%', '.0%', '%') AS CoefficientPercentDisplay,
    se.Effect,
    CASE se.Effect
        WHEN 2 THEN 'Direct School Damage (Magic/Generic)'
        WHEN 7 THEN 'Weapon Damage'
        WHEN 10 THEN 'Direct Heal'
        WHEN 58 THEN 'Weapon Percent Damage'
        WHEN 64 THEN 'Weapon Damage (Normalized)'
        ELSE 'Other / Not Applicable'
    END AS EffectDescription,
    se.EffectAura,
    CASE se.EffectAura
        WHEN 3 THEN 'Periodic Damage (DoT)'
        WHEN 8 THEN 'Periodic Heal (HoT)'
        ELSE 'None / Not Applicable'
    END AS AuraDescription
FROM 
    SpellEffect se
INNER JOIN 
    SpellClassOptions sco ON se.SpellID = sco.SpellID
LEFT JOIN 
    SpellName sn ON se.SpellID = sn.ID
WHERE 
    se.Effect IN (2, 7, 10, 58, 64) OR 
    se.EffectAura IN (3, 8);