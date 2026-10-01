# Character select dresses the Canvas Runner, and everyone in a match varies

Decided by Jarman on 2026-10-01 (after the visual overhaul was pushed):
- The menu's customize screen uses the Canvas Runner (the TDM bot model), not
  jcodes's bean. jcodes's 10 skins become runner outfits; hats/masks become
  helmet toppers/visor pieces; gun skins restyle the whole Paint Blaster.
- Back bling must be MORE diverse than reservoir recolours - each option its
  own silhouette.
- TDM bots get random outfits/gun skins/back bling, including a few bot-only
  outfits the player cannot pick.
- Survival enemies ALSO get cosmetic variety (accessories, patterns), but
  never a change of archetype colour or outline.
- Map pass: same layout and collision, new look (no moved cover/ramps).

Why: once bots and the gun were reworked, the old bean preview no longer
matched anything in a match, and identical bots looked like clones.

How to apply: keep the `customization` dictionary keys (username, skin,
body_color, hat, mask, gun_skin, back_bling) as the contract; visuals read
`record.customization`, so the online branch's remote players can reuse it.
See [[online-branch-direction-differs-from-overhaul]].
