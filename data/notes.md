What tables do we care about?

Spell
    - ID
    - NameSubtext_lang
    - Description_lang
    - AuraDescription_lang


```
SELECT 
    se.SpellID,
    se.Effect,
    se.EffectAura,
    se.EffectBonusCoefficient
FROM 
    SpellEffect se
INNER JOIN 
    SpellClassOptions sco ON se.SpellID = sco.SpellID
WHERE 
    se.Effect IN (2, 10) OR 
    se.EffectAura IN (3, 8)
```