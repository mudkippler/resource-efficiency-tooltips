-- Generates the rows of ns.SPELL_COEFFICIENTS (ResourceEfficiencyTooltips/SpellCoefficients.lua).
-- Paste the output between "ns.SPELL_COEFFICIENTS = {" and "}".
--
-- One row per spell, one {percent,kind} per spell effect in EffectIndex order, with no spaces or
-- comments to keep the shipped file small:
--     [133]={{42.9,"damage"},{0,"dot"}},
-- kind:
--     damage  direct school damage      (Effect 2)
--     heal    direct heal               (Effect 10)
--     weapon  weapon damage, not spell power (Effect 7, 58, 64)
--     dot     periodic damage aura      (EffectAura 3)
--     hot     periodic heal aura        (EffectAura 8)
-- DifficultyID = 0 skips the raid difficulty copies of some effects (e.g. Flame Spear, Blast Wave).
-- A periodic trigger spell aura (EffectAura 23) does its damage or healing through the spell it
-- triggers, so that spell's effects are listed in the aura's place: Arcane Missiles (5143) fires
-- 7268 every second, which has the 28.6% coefficient. Mind Sear and Penance work the same way.
SELECT
    '[' || SpellID || ']={' || GROUP_CONCAT('{' || Percent || ',"' || Kind || '"}', ',') || '},' AS LuaRow
FROM (
    SELECT
        e.SpellID,
        -- 42.9 stays 42.9, 100.0 becomes 100
        CASE WHEN ROUND(e.EffectBonusCoefficient * 100, 1) = CAST(ROUND(e.EffectBonusCoefficient * 100, 1) AS INTEGER)
            THEN CAST(ROUND(e.EffectBonusCoefficient * 100, 1) AS INTEGER)
            ELSE ROUND(e.EffectBonusCoefficient * 100, 1)
        END AS Percent,
        CASE
            WHEN e.EffectAura = 3 THEN 'dot'
            WHEN e.EffectAura = 8 THEN 'hot'
            WHEN e.Effect = 10 THEN 'heal'
            WHEN e.Effect IN (7, 58, 64) THEN 'weapon'
            ELSE 'damage'
        END AS Kind
    FROM (
        -- The spell's own effects.
        SELECT
            se.SpellID, se.EffectIndex, 0 AS SubIndex,
            se.EffectBonusCoefficient, se.Effect, se.EffectAura
        FROM
            SpellEffect se
        WHERE
            se.DifficultyID = 0
            AND EXISTS (SELECT 1 FROM SpellClassOptions sco WHERE sco.SpellID = se.SpellID)
            AND (se.Effect IN (2, 7, 10, 58, 64) OR se.EffectAura IN (3, 8))
        UNION ALL
        -- The effects of the spell a periodic trigger spell aura fires, in the aura's place.
        SELECT
            se.SpellID, se.EffectIndex, ts.EffectIndex + 1 AS SubIndex,
            ts.EffectBonusCoefficient, ts.Effect, ts.EffectAura
        FROM
            SpellEffect se
        INNER JOIN
            SpellEffect ts ON ts.SpellID = se.EffectTriggerSpell AND ts.DifficultyID = 0
        WHERE
            se.DifficultyID = 0
            AND se.EffectAura = 23
            AND EXISTS (SELECT 1 FROM SpellClassOptions sco WHERE sco.SpellID = se.SpellID)
            AND (ts.Effect IN (2, 7, 10, 58, 64) OR ts.EffectAura IN (3, 8))
    ) e
    -- GROUP_CONCAT keeps this order, so each spell's effects stay in EffectIndex order.
    ORDER BY
        e.SpellID, e.EffectIndex, e.SubIndex
)
GROUP BY
    SpellID
ORDER BY
    SpellID;
