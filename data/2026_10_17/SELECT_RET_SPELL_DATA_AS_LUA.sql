-- Generates the rows of ns.SPELL_COEFFICIENTS (ResourceEfficiencyTooltips/SpellCoefficients.lua).
-- Paste the output between "ns.SPELL_COEFFICIENTS = {" and "}".
--
-- One row per spell, one { percent, kind } per spell effect in EffectIndex order:
--     [133] = { { 42.9, "damage" }, { 0, "dot" } }, -- Fireball
-- kind:
--     damage  direct school damage      (Effect 2)
--     heal    direct heal               (Effect 10)
--     weapon  weapon damage, not spell power (Effect 7, 58, 64)
--     dot     periodic damage aura      (EffectAura 3)
--     hot     periodic heal aura        (EffectAura 8)
-- DifficultyID = 0 skips the raid difficulty copies of some effects (e.g. Flame Spear, Blast Wave).
SELECT
    '    [' || SpellID || '] = { ' || GROUP_CONCAT('{ ' || Percent || ', "' || Kind || '" }', ', ')
        || ' }, -- ' || SpellName AS LuaRow
FROM (
    SELECT
        se.SpellID,
        COALESCE(sn.Name_lang, '?') AS SpellName,
        -- 42.9 stays 42.9, 100.0 becomes 100
        CASE WHEN ROUND(se.EffectBonusCoefficient * 100, 1) = CAST(ROUND(se.EffectBonusCoefficient * 100, 1) AS INTEGER)
            THEN CAST(ROUND(se.EffectBonusCoefficient * 100, 1) AS INTEGER)
            ELSE ROUND(se.EffectBonusCoefficient * 100, 1)
        END AS Percent,
        CASE
            WHEN se.EffectAura = 3 THEN 'dot'
            WHEN se.EffectAura = 8 THEN 'hot'
            WHEN se.Effect = 10 THEN 'heal'
            WHEN se.Effect IN (7, 58, 64) THEN 'weapon'
            ELSE 'damage'
        END AS Kind
    FROM
        SpellEffect se
    LEFT JOIN
        SpellName sn ON sn.ID = se.SpellID
    WHERE
        se.DifficultyID = 0
        AND EXISTS (SELECT 1 FROM SpellClassOptions sco WHERE sco.SpellID = se.SpellID)
        AND (se.Effect IN (2, 7, 10, 58, 64) OR se.EffectAura IN (3, 8))
    -- GROUP_CONCAT keeps this order, so each spell's effects stay in EffectIndex order.
    ORDER BY
        se.SpellID, se.EffectIndex
)
GROUP BY
    SpellID
ORDER BY
    SpellID;
