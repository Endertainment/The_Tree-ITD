# Gemini texture prompts

Prompt pack for generating every painted texture slot listed in
[ASSET_SLOTS.md](ASSET_SLOTS.md). Everything here is drop-in: generate → cut out
→ downscale → save under the exact file name → reopen Godot. No code changes.

The prompts are written for **Gemini 2.5 Flash Image ("Nano Banana")** in the
Gemini app or Google AI Studio. Attach both reference images to every prompt.

---

## 0. How to drive Gemini

**Attach both references, every time.** Add this line to the top of each prompt:

```text
Use the attached images ONLY as style reference: the painterly forest world,
palette, lighting and level of detail. Do not copy their layout, camera,
characters, UI panels, legend icons, red skull markers, arrows, borders or any
text from them.
```

**One asset per generation.** Ask for 4 variations, pick the best, then refine by
editing that image ("keep everything identical, only make the trunk thicker")
instead of re-rolling from scratch — edits preserve the design.

**Transparent sprites.** Gemini returns opaque images. Ask for a flat, shadowless
key colour that does not occur in the subject, then cut it out:

| Subject | Key colour |
|---|---|
| Foliage, stone, ice, UI | magenta `#FF00FF` |
| Orcs, wood, red/gold accents | cyan `#00FFFF` |
| Gold/yellow UI | deep blue `#0000FF` |

Cut with `rembg` (best for leaves and fur), or Photopea → *Remove background*,
or magic wand + *Select > Modify > Contract 1px* + *Feather 0.5*.

**Sizes.** Never ask for 128 px — Gemini outputs ~1024 px. Always generate big
and downscale with Lanczos:

```powershell
magick in.png -resize 512x512 -filter Lanczos out.png
```

**Do not bake in:** text, numbers, logos, watermarks, frames, drop shadows on the
ground, baked ground planes, UI, red skull spawn markers or path arrows — the
game draws all of those itself.

**Godot import after dropping the file in:** *Fix Alpha Border* on (kills dark
fringes), *Mipmaps* on for battle art, *Compress → VRAM Compressed (ETC2/ASTC)*,
*Filter* linear. UI atlases: mipmaps off, lossless.

---

## 1. Master style block

Paste this first in every prompt. It is the single source of the look.

```text
ART DIRECTION — "The Tree: Idle Tower Defense", a premium hand-painted fantasy
strategy game for mobile.

STYLE: modern painterly semi-realistic 2D game art. Lush ancient forest fantasy,
the polish of a high-end mobile strategy game, the atmosphere of Ori and the
Blind Forest, the readability of Kingdom Rush. Not photoreal, no cartoon ink
outlines, no cel shading, no anime, no flat vector.

PALETTE: deep forest green #26381f and moss #4e6b3a, warm autumn gold #f2c14e as
the accent, aged ivory and bone, weathered grey-green stone #55604c, turquoise
water and magic #6fd8e8, a little warm amber sunlight. Keep greens dominant and
gold rare so it stays a highlight.

LIGHT: clear 3/4 sunlight from the upper left, dappled leaf shadows, soft warm
rim light on edges, a little atmospheric haze for depth, a few drifting golden
pollen motes. Cinematic but readable when shrunk to 100 px.

MOOD: serene, ancient, sacred, alive — a grove worth defending. Danger only at
the edges.

RENDERING: crisp silhouettes, strong value contrast between subject and
background, fine painted texture, smooth gradients, clean edges for alpha
cut-out. No film grain, no chromatic aberration, no lens flare, no motion blur,
no excessive bloom, no neon oversaturation.

ALWAYS: one subject, centred, fully inside the frame with 5% empty padding, no
text, no letters, no numbers, no logo, no watermark, no signature, no border, no
UI, no multiple views, no turnaround sheet, no collage, no fake readable runes.
```

### Universal negative line

```text
Avoid: text, letters, captions, watermark, logo, signature, frame, border,
collage, character sheet, multiple angles, blurry, low resolution, jpeg
artifacts, plastic 3D look, photo texture, motion blur, extra limbs, extra
heads, cropped subject, neon glow, heavy vignette.
```

---

## 2. Arena ground — `battle/arena_ground.png`

**Target:** 1024×1024, square, 1:1. Maps into the 500 px playfield circle; the
four corners are hidden, so keep detail inside the inscribed circle and put
nothing important in the corners.

```text
Top-down orthographic view straight down onto a circular forest glade arena.
The entire image is the arena floor — no horizon, no sky, no perspective tilt, no
camera angle.

A wide circle of trampled grass, moss and packed earth with worn dirt paths
crossing it. Scattered across it: flat mossy boulders, a couple of fallen
moss-covered logs, small turquoise ponds with lily pads, a thin stream, patches
of wildflowers and ferns, pale twisting roots, faint ancient elven flagstones
half-swallowed by grass. The outer 12% of the frame is dense dark canopy shade
and tree trunks so the glade reads as a clear lit clearing inside a dark forest.

The centre stays open, calmer and free of clutter so units read on top of it.
Warm sunlight dapples from the upper left, soft mist in the shade.

No characters, no creatures, no buildings, no towers, no arrows, no red skull
markers, no boundary ring, no magic circle, no text, no UI. The arena fills the
frame edge to edge, seamless painterly texture.

Square 1:1 composition, 1024x1024.
```

*Why:* the code draws its own gold boundary arc and spawn markers on top, so the
texture must not include them.

---

## 3. World Tree — `tree/tree_body.png`

**Target:** 512×512, square. Pivot is the **trunk base at the bottom-centre**;
`art_offset` defaults to `(0, -96)`, so the trunk base sits low in the frame and
the canopy fills the top.

```text
A colossal ancient World Tree, seen from a 3/4 front view, upright, the whole
tree inside the frame.

The gnarled trunk is pale silver-white bark with deep grooves, splitting into a
wide flared root base at the bottom-centre of the canvas, roots gripping mossy
carved elven stones and a ring of worn flagstones. Faint cyan sap-veins glow
under the bark like liquid moonlight. Above, a vast luminous canopy of pale
jade-green and teal-cyan leaves, layered and painterly, with a soft inner glow,
a few floating glowing leaves and drifting cyan motes. Delicate white branches
catch the light. Warm gold rim light from the upper left, cool teal light from
within the canopy.

Sacred, ancient, alive, protective — not evil, not burning, not dead.
Slightly asymmetric and organic, strong readable silhouette.

No ground plane, no cast shadow on the ground, no characters, no buildings, no
text, no floating UI. Isolated on a flat solid magenta #FF00FF background.
```

---

## 4. Towers — `towers/<id>_l<level>.png`

Three towers × three levels. All are drawn as **static upright billboards**
(height 4.2 × body radius, centred), so paint them standing, front 3/4, base flat
at the bottom edge.

**Generate level 1 once, then edit it for level 2 and 3.** That is the only way
to keep the silhouette identical.

Reusable level-2 / level-3 edit instruction:

```text
Using the attached image as the exact same tower, keep the silhouette, base,
palette and camera identical. Upgrade it to level 2: add ... . Everything else
must stay pixel-for-pixel the same. Still isolated on the same flat key colour,
same framing, no text, no ground.
```

### 4.1 Archer tower — base `#7a4a2b`, accent green `#7ec850`

`archer_tower_l1.png`

```text
An elven archer watchtower, 3/4 front view, upright, fully visible from base to
rooftop, one object only.

Level 1 — humble and small: a single round platform of pale carved wood and
living branches, lashed with rope, a low railing, a small leaf-thatch canopy, a
longbow resting on a rack, ivy and moss creeping up the posts, warm gold trim on
the rail. Base sits flat at the bottom-centre of the canvas, tower occupies about
82% of the canvas height, clear silhouette, a little warm sunlight from the upper
left, a soft green inner glow at the platform.

No ground, no shadow on the ground, no archer, no text, no banner lettering.
Isolated on a flat solid magenta #FF00FF background. Vertical 3:4 composition.
```

`archer_tower_l2.png` (edit prompt)

```text
Upgrade it to level 2: raise it onto a second storey with a taller carved post,
add a second small canopy, two green banners with a simple leaf emblem (no
lettering), reinforced diagonal braces, a hanging lantern with warm light, and a
slightly thicker gold-trimmed railing. Keep it the same tower.
```

`archer_tower_l3.png`

```text
Upgrade it to level 3: three storeys, a masterwork elven design with gold
filigree on the railings, a glowing green crystal core under the top canopy,
hanging lanterns and wind chimes, a larger leaf-canopy roof, faint green motes.
Same silhouette family, richer and taller.
```

### 4.2 Frost spire — base `#5a6b7a`, accent cyan `#6fd8e8`

`frost_spire_l1.png`

```text
An elven frost spire, 3/4 front view, upright, one object only.

Level 1 — a slender hexagonal plinth of pale blue-grey stone carved with simple
elven patterns, topped by a single floating shard of ice crystal glowing pale
cyan from within, a thin ring of frost runes at its base, light snow dust and a
little cold mist curling around the stone. Base flat at the bottom-centre, spire
occupies about 82% of the frame height, clear needle-like silhouette, cool cyan
rim light, warm gold accent only on one small carved band.

No ground, no cast shadow, no text, no readable runes (abstract carved grooves
only). Isolated on a flat solid magenta #FF00FF background. Vertical 3:4.
```

`frost_spire_l2.png`

```text
Upgrade to level 2: taller plinth with a second carved tier, a cluster of three
ice shards instead of one, a ring of small orbiting ice fragments, frost
spreading down the stone, a brighter cyan core and a faint aurora glow.
```

`frost_spire_l3.png`

```text
Upgrade to level 3: a tall slender spire crowned by a large faceted crystal
crown, six orbiting shards, snow drifting, an icy halo ring, carved elven
arches in the stone base glowing cyan, faint blue-white light shafts.
```

### 4.3 Ballista — base `#6b4a2b`, accent steel `#b8c0c8`

`ballista_l1.png`

```text
A wooden siege ballista emplacement, 3/4 front view, upright, one object only.

Level 1 — a heavy timber frame on a low stone base, one thick horizontal bow arm
of dark wood and rope, a loaded iron-tipped bolt pointing forward, coarse rope
binding, iron brackets, a few spare bolts in a rack, moss and wood grain, warm
sunlight from the upper left and a cold steel glint on the bolt head.

Base flat at the bottom-centre, occupies about 82% of the frame height, chunky
readable siege-engine silhouette.

No ground, no cast shadow, no crew, no text. Isolated on a flat solid magenta
#FF00FF background. Vertical 3:4.
```

`ballista_l2.png`

```text
Upgrade to level 2: reinforce with iron plates and rivets on the frame, add a
second bow arm, a winch with a crank, a heavier bolt, a small stack of ammunition
and a torn brown banner with a simple iron sigil (no lettering).
```

`ballista_l3.png`

```text
Upgrade to level 3: a master siege engine with gold-capped iron fittings, carved
elven reinforcements, twin steel bow arms, a glowing golden bolt head, a lantern
hanging from the frame, and a pile of heavy bolts. Richer, heavier, still the
same machine.
```

---

## 5. Orcs — `enemies/<id>.png`

Enemies **rotate to their movement direction** (`rotation = velocity.angle()`), so
every orc must be painted **facing right (+x), seen from a high 3/4 top-down
angle**, centred, with no baked ground shadow or base.

Grunt → 256², Runner → 256², Brute → 384², Warlord → 512².

Shared opening for all four:

```text
A single orc warrior for a top-down fantasy tower-defense game, seen from a high
3/4 top-down angle, full body, facing right (+x), centred in the frame with 8%
padding. Painterly, chunky, readable at 100 px, strong silhouette, warm sunlight
from the upper left, cool bounce light on the underside. No ground, no cast
shadow, no base, no weapon glow, no text. Isolated on a flat solid magenta
#FF00FF background.
```

`orc_grunt.png` — *green, unarmoured, cleaver, mass infantry*

```text
Orc grunt: stocky green-skinned infantry, hunched shoulders, leather scraps and a
rope belt, a crude iron cleaver in one hand, a small round wooden shield in the
other, broken tusks, leather cap, dirt and scratches. Common, cheap, expendable.
```

`orc_runner.png` — *lean, fast, no armour, twin daggers*

```text
Orc runner: lean wiry orc, long limbs, light olive skin, a ragged loincloth and
shoulder strap, twin curved daggers, a wild topknot, leaning forward mid-stride,
built for speed and no armour.
```

`orc_brute.png` — *heavy, iron shoulder plate, giant club, armour 3*

```text
Orc brute: hulking mass of muscle, dark green-brown hide, one huge riveted iron
shoulder plate, a massive spiked wooden club dragging low, thick bracers, a
leather harness, scars, small eyes under a heavy brow. Slow and terrifying.
```

`orc_warlord.png` — *boss, black iron armour, red accents, huge axe*

```text
Orc warlord boss: enormous, blackened iron plate armour with red cloth and
bone trophies, a horned helm, a huge two-handed axe with a glowing red rune in
the blade, a ragged dark-red cape, war paint. Clearly the strongest enemy on the
field, but the same painterly style and palette family.
```

---

## 6. Archer — `archers/archer.png`

Rotates toward its target and fires along +x; drawn 46 px tall, so simplify.

**Target:** 256×256.

```text
A single elven archer of the World Tree, seen from a high 3/4 top-down angle,
full body, facing right (+x), centred with 8% padding.

Female elf ranger: long silver-white hair tied back, pointed ears, green leather
armour with subtle gold filigree, a dark green hooded cloak, a leather bracer, a
quiver of arrows on her back, drawing a long elegant recurve bow with a nocked
arrow pointing right. Calm, precise, sacred-guardian mood. Painterly, readable
when shrunk to 46 px — strong silhouette, simple shapes, no fussy detail.

No ground, no cast shadow, no base, no text. Isolated on a flat solid magenta
#FF00FF background. Square 1:1.
```

---

## 7. Build pad — `battle/build_pad.png`

Top-down, empty, no tower. Drawn at 2.3 × body radius.

**Target:** 256×256.

```text
A top-down orthographic view of an empty elven build pad: a circular platform of
carved pale flagstones set into moss and grass, a thin ring of worn gold inlay,
four small stone plinths evenly spaced around the rim, faint abstract elven
carvings, a little grass and moss creeping between the stones, a soft teal rune
glow in the centre. Completely empty — nothing built on it, no tower, no
character.

Perfectly circular, fills the frame, straight-down view, soft ambient occlusion
at the rim.

No text, no UI, no arrows. Isolated on a flat solid magenta #FF00FF background.
Square 1:1, 256x256.
```

---

## 8. Projectiles — `projectiles/*.png`

Drawn rotated along the shot direction, so **point right (+x)**, thin, centred.

`arrow.png` (128²)

```text
A single elven arrow seen from directly above, pointing right (+x), horizontal,
centred: a slender pale wooden shaft, a sharp steel leaf-shaped head on the right,
green-and-gold fletching on the left, a thin gold band at the nock. Clean, iconic,
readable at 32 px, soft warm highlight along the shaft.

No motion blur, no trail, no text. Isolated on a flat solid magenta #FF00FF
background. Square 1:1.
```

`frost_bolt.png` (128²)

```text
A single shard of ice magic seen from the side, pointing right (+x), horizontal,
centred: a sharp faceted ice crystal with a bright cyan core, a white-blue glow,
a few tiny frost shards trailing behind it, cold vapor wisp. Readable at 32 px.

No motion blur, no text. Isolated on a flat solid magenta #FF00FF background.
Square 1:1.
```

`ballista_bolt.png` (128²)

```text
A single heavy ballista bolt seen from the side, pointing right (+x), horizontal,
centred: a thick dark wooden shaft with iron bands, a broad iron triangular head,
small leather fletching, a faint orange glint on the edge. Heavy and brutal.

No motion blur, no text. Isolated on a flat solid magenta #FF00FF background.
Square 1:1.
```

---

## 9. Menu background — `ui/menu_background.png`

Full-screen behind every tab. **Target:** 1080×1920, 9:16 portrait. Leave the top
and bottom darker and calmer so buttons and panels stay readable; keep it soft
(no hard focal contrast behind the UI).

```text
A portrait, full-screen menu background for a fantasy tower-defense game.

A moonlit ancient forest glade seen from a slightly elevated 3/4 angle: the
World Tree stands in the middle distance, its luminous jade-and-cyan canopy
glowing softly, pale roots and carved elven stones at its base, a winding mossy
path leading to it through ferns and fallen logs, fireflies and drifting glowing
motes, thin shafts of moonlight through the canopy, soft mist pooling low.

Composition: tall portrait 9:16, the tree in the lower-middle third, the upper
third filling with dark canopy and a few leaves so a title and buttons read
clearly over it, the bottom fading into dark mossy ground for the tab bar. Deep
greens, teal glow, restrained gold.

No characters, no towers, no enemies, no UI, no panels, no text, no logo, no
border, no vignette frame — just the painted environment. Painterly, calm,
inviting.
```

---

## 10. UI skin — `ui/*.png`

9-patch rules: the skin's corner margin is a fixed **36 texture px**, so the
frame's border and corner rounding must live inside the outer ~7% of a 512 px
image. Keep it flat, no baked text, no icons.

### 10.1 Panel — `ui/panel.png` (512², 9-patch)

```text
A 9-slice UI panel for a fantasy strategy game, seen straight on, filling the
whole square frame: a dark forest-green glass surface (#1d2a1f, 90% opaque) with
a thin warm gold border line (#f2c14e) inset about 1% from the edge, softly
rounded corners with a radius of about 7% of the image, a very subtle inner
highlight along the top edge and a faint dark inner shadow at the bottom, a tiny
gold corner ornament in each corner inside the outer 7% only, otherwise a flat
plain centre suitable for stretching.

Clean, crisp, symmetrical, no text, no icons, no drop shadow outside the panel,
no perspective, no texture noise. Flat solid background outside the rounded
corners for keying — use a flat solid blue #0000FF outside the panel so the
corners can be cut out. Square 1:1.
```

### 10.2 Buttons — `ui/button_<state>.png` (crop to ~3:1)

Generate 16:9, crop to 3:1, downscale to 360×120. The outer 36 px must contain
the corner and border.

`button_normal.png`

```text
A wide horizontal UI button for a fantasy strategy game, front view, flat and
clean, 3:1 wide aspect.

Dark mossy green lacquered surface with a subtle wood grain, a thin warm gold
border with slightly rounded corners, a soft top highlight, a deeper green
bevel at the bottom, and a small gold leaf ornament centred on the left and right
ends only (no text, no icon in the middle). Empty middle area for stretching.

Crisp, symmetrical, no text, no letters, no shadow outside the button. Flat solid
blue #0000FF background outside the rounded corners. Wide 16:9 image, the button
filling the frame with a small margin.
```

Then derive the other three by editing:

| State | Edit instruction |
|---|---|
| `button_hover.png` | "Same button, brighter: raise the gold border brightness, add a faint warm glow inside the top edge, lift the green surface slightly." |
| `button_pressed.png` | "Same button, pressed: darken the surface ~20%, invert the bevel so the bottom highlight becomes an inner shadow, shrink the gold border thickness slightly." |
| `button_disabled.png` | "Same button, disabled: desaturate to grey-green, drop the gold to a dull brass, flatten all highlights, 55% opacity feel." |

`button_primary_<state>.png` — the gold CTA

```text
Same wide fantasy UI button shape, but the hero call-to-action variant: warm
antique gold surface (#f2c14e) with a subtle engraved laurel pattern, a darker
bronze border, a bright cream highlight along the top, a warm inner glow. Rich
and inviting, the most prominent button on screen. No text, no icon.
```

`button_danger_<state>.png`

```text
Same wide fantasy UI button shape, danger variant: deep crimson and dark iron
surface (#7a2a24), a blackened iron border, a thin ember-orange line, a subtle
cracked-leather texture, a hot ember glow at the bottom edge. Threatening but not
neon. No text, no icon.
```

`tab_<state>.png` — bottom tab, roughly 1:1

```text
A square bottom-tab button for a fantasy game UI: a small rounded stone plate
with a thin gold rim and a subtle inner glow, centred, with an empty recessed
circle in the middle where an icon will sit. Normal state: muted mossy stone.
No icon, no text, no label. Flat solid blue #0000FF outside the rounded frame.
```

### 10.3 HP bars — `ui/hp_bar_bg.png`, `ui/hp_bar_fill.png`

Stretched, not 9-patch. **256×32 each**, same shape so the fill lines up.

```text
A horizontal health-bar background, 8:1, viewed flat: a rounded dark iron trough
with a thin black outline, a subtle inner bevel, empty inside, no fill, no text,
no numbers, no gloss. Crisp game UI, readable at 120 px wide. Isolated on a flat
solid blue #0000FF background, the bar centred and filling the frame.
```

```text
The matching health-bar fill for the same trough: the identical rounded 8:1 shape
and outline, filled edge to edge with a warm gradient from deep forest green on
the left to bright leaf green on the right, a soft lighter highlight along the top
third, clean and flat. No text, no numbers, no gloss line outside the shape.
Isolated on a flat solid blue #0000FF background.
```

---

## 11. App icon and splash (optional, after the art is locked)

`icon_main_192.png` / adaptive foreground — 512², mark only, transparent.

```text
A game app icon mark: a stylised sacred World Tree emblem, front view, perfectly
centred and symmetrical, drawn in warm antique gold (#f2c14e) with a thin dark
outline, its canopy a clean geometric leaf-cluster silhouette and its roots
forming a subtle circular ring. Sumptuous, minimal, high contrast, readable at
48 px. No background, no text, no letters, no shield, no banner.

Flat vector-like rendering, crisp edges. Isolated on a flat solid magenta #FF00FF
background. Square 1:1.
```

Adaptive background: flat `#1d2a1f` (paint this one in any editor — do not
generate it).

Splash — 1080×1920, 9:16:

```text
A portrait boot splash for a fantasy tower-defense game: a dark, softly
vignetted deep-forest-green background with faint painterly tree silhouettes and
a band of drifting golden motes, the sacred World Tree emblem glowing faintly in
gold in the centre, generous empty space around it. Calm, premium, no text, no
logo lettering, no UI.
```

---

## 12. Optional: heroine portrait (menu / results)

Ideal reference for the elf on the central platform. **3:4, 1024×1365.**

```text
A full-body elven ranger heroine, 3/4 front view, standing in a relaxed archer's
stance, seen from slightly below eye level.

Long silver-white hair braided back, pointed ears, an elegant dark-green leather
armour with gold filigree, layered leaf-shaped pauldrons, a long dark green cloak
with a subtle embroidered leaf pattern, a carved longbow in one hand, a quiver on
her back, a calm determined expression. Painterly, semi-realistic, warm gold rim
light from the upper left, cool teal magic light from the lower right.

Dark neutral background, no ground, no text, no UI, no companion. Vertical 3:4.
```

---

## 13. File map — save exactly here

| Generate | Save as | Ship size |
|---|---|---|
| Arena ground | `assets/art/battle/arena_ground.png` | 1024² |
| World Tree | `assets/art/tree/tree_body.png` | 512² |
| 3 towers × 3 levels | `assets/art/towers/<id>_l<level>.png` | 384×512 |
| Tower fallback (optional) | `assets/art/towers/<id>.png` | 384×512 |
| Orcs | `assets/art/enemies/orc_grunt.png` etc. | 256² / 384² / 512² |
| Archer | `assets/art/archers/archer.png` | 256² |
| Build pad | `assets/art/battle/build_pad.png` | 256² |
| Projectiles | `assets/art/projectiles/{arrow,frost_bolt,ballista_bolt}.png` | 128² |
| Menu background | `assets/art/ui/menu_background.png` | 1080×1920 |
| UI panel / buttons / tabs | `assets/art/ui/*.png` | panel 512², buttons 360×120 |
| HP bars | `assets/art/ui/hp_bar_{bg,fill}.png` | 256×32 |
| Android icon | `assets/art/android/*.png` | 192² / 432² |
| Splash | `assets/art/splash.png` | 1080×1920 |

Tower IDs are exactly `archer_tower`, `frost_spire`, `ballista` (three levels
each); enemy IDs are `orc_grunt`, `orc_runner`, `orc_brute`, `orc_warlord`.

---

## 14. Suggested order of work

1. **Arena ground** — it sets the light and palette for everything else.
2. **World Tree** — the hero asset; iterate until the glow reads at 200 px.
3. **One tower (archer L1)**, then derive L2/L3 by editing.
4. **Frost spire and ballista**, same L1 → edit flow.
5. **Orcs** — grunt first, then derive the other three from it.
6. **Archer + build pad + projectiles** — small, quick.
7. **Menu background**, then UI panel and button states.
8. **Icon and splash** last, once the look is locked.

Keep the two reference images attached for the whole run, and once you have a
good arena + tree, feed those two back in as the style anchor — that combo
holds the palette far better than the originals alone.

---

## 15. Quick quality checks

- Shrink the result to its **ship size** and look at it: if the silhouette is
  unclear at 100 px, regenerate — the game draws it small.
- Check that nothing in the sprite is pure magenta/cyan that you want to keep.
- After keying, zoom to 400% at the edges: leaves and fur should have clean,
  slightly feathered alpha, no dark halo.
- The ground must not contain a boundary ring, arrows or skulls — the code draws
  those.
- Towers must sit flat on the bottom edge; if the base floats, the tower will
  hover above the pad.
- Enemies and the archer must face **right** before import, or they will run
  backwards.
