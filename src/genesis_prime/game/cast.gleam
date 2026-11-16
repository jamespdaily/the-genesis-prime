//// A player's casts, a feature of the game connection's rule
//// (genesis_prime/game/connection) as movement and chat are: the press of an
//// ability on the action bar, the answers the client expects, the cast bar and
//// cooldowns it keeps, the cast's go and finish, the child casts a Proxy effect
//// starts, the thresholds of a RapidTap or ChargeRelease ability, and the cast's
//// end when the client cancels it. The caster's connection owns its casts and
//// sends every message about them; it tells the connections that see its player
//// the same news, which they write for a cast they know.
////
//// ```
//// client                    connection (this rule)                         viewers' connections
//// 0x9a press ──────────────▶ decode; bag index ─▶ the ability's tree (genesis_prime/game/spell_plan)
////                            an open threshold of the ability ─▶ the stage its index names
////                            a refusal of the client's own checks ──▶ 0x7fc {client id, Spell4 id, result}
////                            the spell's cast conditions last (CasterCast 151, TargetCast 281)
////                            accepted: id k = mint(unit, n); the gcd starts
//// ◀── 0x7fd {client id, k, caster}                  (the caster's cast starts in its client)
////                            Tell(each viewer, CastStarted)  ──────────────▶ 0x7ff, when its client shows the caster
//// ◀── 0x816 {ability, ability, 0, k}   a RapidTap or ChargeRelease ability's first press opens its threshold
//// ◀── 0x817 {ability, index}           the next tap's stage, or the next charge level (a timer)
////                            cast time 0: the go at once; else StartTimer(go)
//// ◀── 0x7f4 {k, phase 0, no target, no effect}  ◀── Tell(each viewer, CastWent) ─▶ 0x7f4, for a cast it wrote
////                            the spell's own cooldown starts at the go its method names
////                            each Proxy of the phase: StartTimer(delay), or at once for delay 0
////                            a child: id k2 = mint, root = the pressed spell, parent = the proxying spell
//// ◀── 0x7ff {k2, ..}        Tell(each viewer, CastStarted) ───────────────▶ 0x7ff
//// ◀── 0x7f4, 0x7fe          its go and finish, as the pressed cast's
//// ◀── 0x7fe {k}             Tell(each viewer, CastFinished) ──────────────▶ 0x7fe, for a cast it wrote
//// ◀── 0x814 {ability, bit}  the last tap or the release closes the threshold
//// 0x801 {k, 6, 1} ─────────▶ the cast ends: its timers cancelled, 0x7fe to all
////
//// each input in the world ─▶ `persisted`: a lasting cast whose persistence stopped holding
////                            ends ──▶ 0x7f9 {k, 282 or 283, caster, 0}, then 0x7fe {k}; Tell(each viewer, CastFinished)
////
//// each input ─────────────▶ `settled`: the stealth change ──▶ StealthChanged (0x8f5), then the procs held for the
////                            input's events (its own: Died, LeftCombat or a hit's; then EnteredStealth or LeftStealth) cast
////                            their spells ──▶ 0x7ff {k, root and parent the holder's spell}, no 0x7fd
////
//// 0x4db held 1 ────────────▶ the ability is held: the same press, with the id k minted and no 0x7fd
////                            its cast over and its cooldowns run ─▶ the same press again (StartTimer(repeat))
//// 0x4db held 0 ────────────▶ the ability is not held: the repeat timer cancelled; a charge fires its stage
//// ```
////
//// - **The press** is 0x9a inside 0x038C: the client's cast id, the ability's bag
////   index, the target and the press bit (`opcode.0x9a`). A cast id of 0 is one
////   the client never sends, and ends the connection. A press bit of 0 is a
////   console setting's; the press is logged and ignored. A bag index the player
////   does not hold is answered 0x7fc with Spell4 id 0 and result 4
////   (`0x14039a040`; the server's choice, which the client allows).
//// - **The hold** is 0x4db: the client sends it instead of 0x9a under its default
////   hold-to-continue-casting setting, once with held 1 at key down and once with
////   held 0 at key up, with no cast id of its own (`opcode.0x4db`). A held 1 is the
////   same press as a 0x9a's with two differences: the server mints the cast id and
////   writes 0x7ff in place of 0x7fd (a 0x7fd names a pending cast the client does
////   not make), and a refusal is a 0x7fc with client cast id 0
////   (`cast.hold_answer`). The client holds no repeat timer, so while the key is
////   held the server casts the ability again, when its last cast is over and the
////   global cooldown it started and the ability's own cooldown have ended, on a
////   timer of the rule; a press behind another cast waits for its end, never
////   refused 13, which the client hides under the setting (`cast.hold_repeat`; the
////   server's choice). A second ability's held 1 replaces the held one, and a second
////   held 1 of the held ability is the same hold. Held 0 ends the repeats and cuts
////   no cast or channel short; for a ChargeRelease ability it fires the charged
////   stage, and a RapidTap ability's repeats are its next stages inside its
////   threshold (`cast.hold_by_method`, `cast.hold_stop`). A refused repeat ends the
////   hold, and so does a 0x801 naming the hold's last cast (the server's choice: a
////   cancel is the player's intent to stop, so a cancelled charge neither restarts
////   nor fires at the held 0 that follows). A bag index with no ability is answered as a 0x9a's is.
//// - **The target** of every cast is the caster: no level-1 ability needs a
////   target the client picks (`Spell4TargetMechanics.targetType`: the client makes
////   the caster the target of a spell of kind 0, 2, 6 or 7 before it sends), so
////   the press's target is not read, and the target checks of the client (91, 105)
////   wait for the first ability that needs one. Who a spell strikes is the area its
////   effects name, which a later step reads.
//// - **The refusals** are the client's own checks, answered 0x7fc with the
////   client's result and clearing the client's global cooldown: 57 for a dead
////   caster's press of a spell whose caster condition row has the dead bit, and
////   58 for a living caster's press of one whose row asks for a dead caster
////   (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`; the row's other
////   conditions are not checked); 13 while the
////   caster's current cast is live (below); the caster result of the lowest state the
////   caster holds that the spell's Spell4CCConditions caster row masks (73 for Stun,
////   302 for Ability Restriction, and so on, `crowd_control.caster_result`) while a cast
////   of the caster holds it on the caster, checked after 13 and before the cooldowns
////   (`CheckSpellCCConditions`, `0x1403b2c40`; `0x1403afb10.order`); 14 while the global cooldown has more
////   than 500 ms left, for kinds 0 and 2; 15 while the spell's own cooldown has
////   more than 500 ms left (`0x1403b14c0`); a caster requirement's result when the
////   caster's resource fails it and the spell's waiver does not pass (`0x1403b1780`,
////   `Rampage` 51 below 250 Kinetic Energy unless the caster is under Overdrive 42908);
////   50 + the resource slot for a cost the caster's class
////   resource cannot pay (`0x1403b3320`, `0x1405e7980`,
////   `Spell4CastResult.vital_cost`); 169 for a spell that needs the weapon when
////   slot 16 holds none (`0x1403afb10`); 151 for a spell whose CasterCast fails and
////   281 for one whose TargetCast does, the last checks of the press (`0x1403ace00`,
////   below); and 285 for a spell whose method is not
////   one of Normal, Multiphase, Channeled, RapidTap and ChargeRelease
////   (`Spell.CodeEnumCastMethod`). A cost in a vital the server does not hold, a cast
////   condition it cannot read and a method not built are each logged once on the
////   connection for the coverage measure. The caster's checks run in the client's
////   order (`Verdict`). A class vital cost (types 4, 12, 13, 14, 18 and 19 on a Spell4
////   row, 18 and 19 on a threshold row) is looked up in the casting class's own slots
////   (`Class.vitalEnumResource00` to `07`, `class_resource.class_cost` and
////   `row_class_cost`): the innate cost passes at the first slot naming the vital whose
////   value less the cost lies in [0, that slot's maximum] and pays from it, and is
////   refused with the last such slot's 50 + slot (177 for slot 7); a class with no slot
////   naming the vital passes and pays nothing (`0x1405e7980`). A threshold row's cost
////   passes at most the whole points of the first slot holding above 0, with no maximum,
////   and is refused with that slot's result, or 175 when the vital's slots hold nothing
////   (`0x1403c0620`, `0x1405e78c0`, `0x1403d3650`).
//// - **The cast conditions** are the spell's prerequisiteIdCasterCast and
////   prerequisiteIdTargetCast, which the client checks after every other check of the
////   press, CasterCast first (`0x1403ace00`, `Spell4.prerequisiteIdCasterCast`), so a press
////   that fails several gets the client's first failure; the check runs only on the path
////   that would accept, since a press the client queues (317) is sent unchecked. The first
////   unit is the caster, and the second unit too: the server reads no target and the client
////   makes the caster the target of every spell it presses. A press held for a cooldown or
////   behind the current cast is checked when it starts, as one the client sent unchecked is
////   (`Spell4.prerequisiteIdCasterCast`), and a held key's repeat each time. A spell with a
////   caster requirement block and propertyFlags bit 2 is not gated by its CasterCast: that
////   prerequisite only waives a failed requirement (`0x1403b1780`). A condition of a type
////   the server does not read, or a type 37 roll (a press draws none), refuses with the
////   check's result and a warning once for the spell (the server's choice, as for a cost in
////   a vital it does not hold).
//// - **A cost is checked at the accept and paid at the cast's first go** (`Pay`): the
////   client checks a cost only before it sends a press, lowers no resource itself and
////   shows only what 0x935 says, so when to pay is the server's
////   (`Spell4.innateCost0.timing`), and a retail video shows the Actuators of Gamma
////   Rays dropping when its beams go off. The accept checks the costs against the slot
////   less what the live casts have reserved (`unreserved`) and keeps them on its live
////   cast (`Live.reserved`); the first go pays them as its strike begins, so the round's
////   hits are always paid for and the go's gates and gains read the paid caster, as
////   one 0x935. A cast that ends before its first go (a 0x801, death, leaving) pays
////   nothing, and its reservation ends with it. A spell whose first go is at once, or
////   that has no go of its own, pays at its accept, in the step of its check
////   (`pays_at_accept`). A second press taken in the same step is checked against what
////   the first left (genesis_prime/game/class_resource).
//// - **A spend of every point held** (`spell_plan.SpendAllCost`, genesis_prime/game/spend):
////   the check is of the base cost alone, as the client's is (`0x1403b3320`), and the
////   accept then reserves every whole point the slot holds less the reserved, which the
////   first go takes and whose new value the client is sent (`opcode.0x935`). The points
////   above the base cost are the cast's n, fixed at the accept (at the start of a held
////   press, which is checked and reserved then), kept on
////   the live cast, and read at each go: the go's strike (`GoAsked.spent`), gains and
////   Proxies are the ones whose tag holds for n. A child a Proxy starts has no n and
////   keeps every effect. A cost with an EMM id the server does not read
////   (`spell_plan.UnreadSpendCost`) is refused with the cost's result and logged once.
//// - **The current cast** is the client's: a cast whose spell shows a cast bar
////   (`spell_plan.shows_cast_bar`) is the caster's current cast from its start. Its
////   go clears it for a Normal cast with a cast time and no parent, and a cast
////   that is itself the current cast clears it at its go unless its method is
////   Multiphase, ChargeRelease or PressHold or it is a channel; any cast's finish
////   clears it, and a 0x801 clears it whatever cast it names. The client refuses
////   a press with 13 only against it, and not when its spell is free while live or
////   the pressed spell ignores casting (`cast.current_cast`, `Spell4.propertyFlags`,
////   `0x1403afb10`). The server keeps the same in `current`.
//// - **A press during the current cast is the server's choice.** The client itself
////   never refuses an ability press with 13 and never queues one behind its current
////   cast: its casting test runs only for a request whose word 0x14 is non-zero,
////   which a press leaves 0 (`cast.press_queue`). The server models that unused test
////   with the same window as the cooldown queue: a press with more than 500 ms of
////   the current cast left (its start plus its duration, `spell_plan.duration_ms`,
////   less the time now) is refused 13, and one with 500 ms or less left is held and
////   starts at the go or finish that clears the current cast, not from a timer. A
////   cast that has no end of its own, a charge held until its release, always
////   refuses.
//// - **A press within 500 ms of a cooldown's end** is held: the client queues it
////   (317) and sends it (`0x1403b14c0`), so the server starts it when the
////   cooldown ends, from a timer, and answers nothing before. A second press
////   while one is held is refused 13 (the server's choice). The held press keeps
////   the stage it resolved to when it came, as the client does. The release of a
////   ChargeRelease threshold is resolved before any caster check, so a held press
////   neither refuses it nor is changed by it (`0x1403bfd60`).
//// - **The cast id** is 2^31 + unit id x 2^11 + n mod 2^11, skipping an id a live
////   cast of the caster holds: unique among the live casts of every unit, since
////   the client keeps one table of casts (`0x140561c30`) and unit ids are below
////   2^20, and never 0. The client's own counter makes no collision: its
////   pending casts live apart (`cast.pending_table`). A child takes the next id.
//// - **The cast bar and cooldowns** are the client's own: 0x7fd and 0x7ff start
////   the caster's global cooldown (`0x14046afc0`, kinds 0 and 1), and a go starts
////   the spell's own (`0x14046b1e0`), so the server sends no 0x804. The server
////   keeps the same, to refuse what the client would: the global cooldown from the
////   accept for the SpellCoolDown time, the spell's own where its method says
////   (`spell_plan.CooldownStart`, `0x14053e5a0`), the child casts none (kind 3).
//// - **The go** is 0x7f4 with the cast id, the ignore-cooldown bit 0, the caster's
////   place as the destination, no target, no position and no missile, and the
////   phase (`opcode.0x7f4`): a go that names no target carries no damage, which
////   the next step adds. A Multiphase spell's phase is the phase's index and a
////   channel's the pulse's (`opcode.0x7f4.phase`). Each go is followed by the
////   spell's Proxies of that phase, and the finish, 0x7fe, comes after the last go,
////   at once for a spell that is not Multiphase. A channel ends at the later of its
////   finish timer and the close of its last go's strike round, so the client has
////   all of its gos before the 0x7fe (`cast.channel_sequence`).
//// - **A go's gains** (`Gain`) are the spell's own gains of the phase and, once
////   for the go and not once per unit, the gains of each Proxy of the phase aimed
////   at each struck unit when the round has a Hit and the Proxy's gate passes
////   (`spell_plan.Gain`). Each is given when its caster apply and target apply
////   prerequisites pass against the caster, the only unit a gain reaches
////   (genesis_prime/game/prerequisite): the spells of the caster's own live
////   casts whose primary target it is, whether it is in combat, its health, shield
////   and the class resource slot it holds as the vitals 1, 3 and 5 to 11, and the
////   rolls the connection drew. A prerequisite of a type or a vital not read, and a
////   ticking gain, give nothing and a debug line. A creature's cast on the player is not
////   held here, so a prerequisite cannot find one (no kit prerequisite tests a
////   creature's spell).
//// - **A go's gates read the caster as it stood before the go's own effects.** The
////   gates of its Proxies and of its gains see the live casts with this go counted,
////   but not the children the go starts and not the cast's removal at its finish: a
////   server choice, since the client applies no Proxy itself
////   (`Spell4Effects.effectType.26.dataBits06`). A gain that asks to be "not under"
////   a spell this same go starts is given (`cast_gate_test`).
//// - **A go's lasting effects** (genesis_prime/game/lasting): each Fluff (17), Scale (18),
////   ItemVisualSwap (76), RavelSignal (81) and SpellForceRemove (80) effect of the phase whose gate against the
////   caster passes is listed in the target info of each unit its targetFlags aim at, with
////   the effect's delay, a result bit, the instance count 1 and the lifetime 0 the client
////   works out itself; a unit the round did not strike gets an info of its own
////   (`opcode.0x7f4.target_info`, `opcode.0x7f4.effect_time`). A Fluff, Scale,
////   ItemVisualSwap or RavelSignal effect gives the unit a node of the cast that lives as long as its
////   longest effect, kept on the live cast; a type 80 effect takes the matching nodes of the caster's casts off the
////   unit, oldest cast first, each written 0x811 (`opcode.0x811`); and a cast that
////   gives a unit a node it holds none on takes off the caster's oldest casts of its
////   stack at the stack's cap (Jim's decision, `Spell4StackGroup.stackCap`).
//// - **A go's property modifiers** (genesis_prime/game/unit_properties): each type 11
////   and type 145 effect of the phase that has a life (a durationTime, or flags bit 2) and
////   whose gate against the caster passes is listed on the caster like a Fluff effect, gives the
////   caster's node its life, and starts at the go plus its delay and ends after its
////   duration, as `CasterChangeStarts` and `CasterChangeEnds` for the connection to apply to the
////   player's properties. A modifier ends on a timer of its own and not with the node's
////   time (a node can outlive it, or end before it when the spell takes the larger of
////   delay and duration); taking the cast's node off the caster ends its modifiers and
////   cancels their timers; the caster's death ends every modifier of its casts but the
////   innate passive's, and every one still pending but the passive's; a later go of the cast arms each again from that go; the player
////   leaving ends none, since the connection's properties go with its player. These
////   are the server's choices: the client works out no property.
//// - **A go's property modifiers on creatures** (type 11 rows whose targetFlags name a
////   unit other than the caster, a `StruckChange`; 3, 5 and 7 also change the caster, in
////   a row of their own, and a unit the flag names twice takes it once): each is aimed
////   at the creatures the go hit, and at the primary target when the flag's bit 2 names it, in the life and at the
////   time the go struck them (`HitCreature`), listed on each like a Fluff effect and
////   giving its node the row's life. The cast owns the time and the creature the values:
////   the rule tells the creature `TargetChangeStarts` at the go plus the row's delay, in
////   the go's own step when there is none, and keeps what it started in `on_creatures`.
////   It has no end timer of its own: it ends, as `TargetChangeEnds` told once, when the
////   cast's node on that creature ends by time, is taken off by a type 80 removal or a
////   push off by the stack rule, when the creature leaves the caster's sight, when the
////   cast's persistence stops holding, when the caster dies (but for the innate passive's
////   cast) and when the player leaves; a start still waiting for its delay is cancelled
////   with it and told nothing. A later go of the cast on the same creature starts it
////   again from that go. A row aimed at another player is left out until a modifier on
////   another player is built (#570), and the stacking of casters' modifiers on one
////   creature is not built (#569).
//// - **A go's throws of creatures** (type 3 rows whose targetFlags name a unit other than
////   the caster, a `StruckMove`, genesis_prime/game/forced_move; 3, 5 and 7 also move
////   the caster): each is aimed at the creatures the go
////   hit, in the life and at the time the go struck them. The rule tells
////   `ForcedMoveStarts` at the go's own step when the row has no delay, and else arms a
////   `ForcedMoveStart` timer for the go plus the row's delay; the end of the cast's node
////   on that creature cancels a timer still waiting (`creatures_ended`), as it cancels a
////   modifier's start. The connection carries `ForcedMoveStarts` out
////   (genesis_prime/game/connection/casting): it draws the throw's two fractions from its
////   seed then, so a delayed throw draws at its own time, and tells the creature. A
////   connection that is gone has no timers, so nothing is thrown.
//// - **A go's disguises** (genesis_prime/game/look): each type 112 effect of the phase
////   that has a life and whose gate against the caster passes is a modifier row whose change is a
////   `Look`, so it is listed, started, ended, cancelled with the node and ended at death
////   by the modifiers' rules above, as `CasterChangeStarts` and `CasterChangeEnds`; the
////   connection turns them into the player's 0x933 and its viewers' `LookChanged`
////   (genesis_prime/game/connection/look). The rule keeps no look: two disguises on one
////   slot, the base and what shows are the look's.
//// - **A go's Interrupt Armor** (`Spell4Effects.effectType.52`): each ModifyInterruptArmor
////   row of the phase that reaches the caster (genesis_prime/game/spell_plan
////   `PropertyModifier.armor`) is a property modifier of property 44, the armor's maximum,
////   and goes through every rule of the property modifiers above: the same listing, node
////   life, start, timer, end and removal. The player's armor follows its maximum
////   (genesis_prime/game/player_life `armor_followed`), so the rule asks nothing more of
////   the connection for it. The client has no case for the effect, so the armor and its
////   maximum are the server's (`Spell4Effects.effectType.52`,
////   `opcode.0x938.interrupt_armor`).
//// - **A go's heals** (`Spell4Effects.effectType.10` and `.118`): each Heal or HealShields
////   effect of the phase that reaches the caster (genesis_prime/game/spell_plan `Heal`)
////   whose gate against the caster passes is listed in the caster's target info with a
////   damage description of its amount (type Heal or HealShields, result Hit, the amount as
////   the raw, the scaled raw and the health change, and as the overheal what the amount
////   leaves over the vital's room), which the client shows as a floater and logs itself
////   as a heal with that overheal, and never applies (`spell.heal_result_log`). The amount
////   is worked out at the go from the caster's own shield, health and stats as they stood
////   before the go's own effects (genesis_prime/game/damage `amount_on_caster`: Energize
////   is 0.3 of the missing shield), and lands at the go plus the row's delay as
////   `CasterChangeStarts` with a `Heal` change carrying the vital, for the connection to
////   raise the player's health or shield by (genesis_prime/game/player_life `healed`): in
////   the go's step, after its 0x7f4, with no delay, else on a timer. A heal gives the
////   caster's node a life of its delay, so the 0x7fe waits for it; when the node's end and
////   a pending heal are due in the same millisecond the end lands the heal first. A node
////   taken off the caster, a persistence that stops holding and the caster's death drop a
////   pending heal with its timer; a later go of the cast heals again and cancels no
////   earlier heal. A periodic heal (a tickTime) heals the caster at each tick, after
////   the tick's 0x7f8 (`ticking_heals`). A heal on a unit other than the caster (a child on a
////   struck unit) lands nothing and a debug line says so (#570). The server rolls no
////   critical for a heal: the description is always a Hit, so the seed draws nothing for
////   it (the server's choice; the crit of a heal is #336).
//// - **A go's absorbs** (`Spell4Effects.effectType.29`): each Absorption effect of the phase
////   that reaches the caster, has a lifetime (a durationTime, or flags bit 2), is not
////   periodic and whose gate against the caster passes is listed in the caster's target
////   info like a Fluff effect, gives the caster's node its life, and starts a pool on
////   the caster, as a heal and a property modifier do, from the amount worked out at
////   the go from the caster's stats as they stood before the go's own effects
////   (genesis_prime/game/damage). The plan reads a type 29 row as a property modifier row
////   whose change is an `AbsorbChange` (genesis_prime/game/spell_plan), so it goes
////   through the same listing, node life, timers, end and removal. The sequence of one go:
////
////   ```
////   go ─▶ 0x7f4 lists the row on the caster
////      ─▶ no delay: CasterChangeStarts(source, Absorb(amount, mask)) in the go's step, after its 0x7f4
////         delay:    a ModifierStart timer of the delay
////      ─▶ ModifierEnd timer at delay + duration, none for flags bit 2
////   ModifierStart fires ─▶ CasterChangeStarts(source, Absorb(amount, mask))
////   ModifierEnd fires   ─▶ CasterChangeEnds(source)
////   ```
////
////   A pool ends on a timer of its own, as a property modifier does, and the connection
////   ends it by source (genesis_prime/game/connection/absorption), where a pool the
////   hit rule used up is already gone and the end writes nothing: the cast keeps its
////   node's time when its pool is spent (a server choice). Taking the cast's node off
////   the caster ends the pool of each row and cancels its timers; the caster's death
////   ends every pool of its casts and cancels the pending ones, after the life dropped
////   them; the player leaving ends none, since the life goes with its `Entered`; a later go
////   of the cast arms each pool again from that go, which refills a pool still held.
//// - **A go's forced moves** (`Spell4Effects.effectType.3.player`): each type 3 effect of
////   the phase aimed at the caster whose gate against the caster passes is listed in the
////   caster's target info with its delay, and nothing more: the caster's client works out
////   the destination, moves its own unit and reports the move in its next 0x637, which
////   the movement rule takes as any other. A forced move gives no node a life, starts no
////   timer and changes no property.
//// - **A go's cooldown effects** (`Spell4Effects.effectType.73`,
////   genesis_prime/game/cooldown): the spell's own cooldown and a stage's ability
////   cooldown start before the go's effects apply, as in the client (`0x14053e5a0`), so
////   a type 73 effect of the phase aimed at the caster whose gate passes already sees
////   them. It is listed in the caster's target info with its delay, and it changes the
////   running cooldowns it picks at the go plus its delay: in the go's step with no
////   delay, on a timer with one. An effect whose lifetime (delay plus duration, the
////   larger of the two for a spell with the record flag 0x10000000, never ending with
////   flags bit 2) ends after its start is also kept for the cooldowns that start later
////   and dropped on a timer at the end of its lifetime; any other acts once
////   (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every such effect gives the caster's
////   node its lifetime, so the 0x7fe, which destroys the effects still pending
////   (`opcode.0x7fe`), waits for them; when the node's end and a pending start are due
////   in the same millisecond the end applies the start first. Taking the cast's node
////   off the caster, the caster's death and its leaving drop the kept effects and
////   cancel their timers, pending starts included, and a later go of the cast keeps
////   each again from that go; the cooldowns an effect changed stay changed. The global cooldown is never changed (`0x14046b920`) and the server sends
////   no 0x804, which would undo the change. After a change a press held for a cooldown's
////   end and the hold's repeat wait for the new end, a timer of 0 ms when it ended: the
////   server's choice. Group cooldowns are not kept.
//// - **A player's stealth** is the Stealth rows (effect type 83) its casts hold on it,
////   by cast id and effect id (`State.stealth`), kept with whether damage ends each
////   (`spell_plan.Breaks`); the player is stealthed while it holds any (`stealthed`).
////   A go lists each Stealth row of its phase whose gate passes against the caster in
////   the caster's target info and holds the caster's node until it is removed (a Stealth
////   row with no durationTime lasts until removed), and adds its source; a RemoveStealth
////   row (type 84) ends every source. After the go's effects, a spell whose
////   `stealth_change` ends stealth at that go (value 0 at each go, value 1 at the cast's
////   last) ends every source of the other casts (`Spell4.spellCastStealthChange.break`;
////   the server's rule): the cast of each loses its node on the caster as a type 80 removal takes it off (0x811, and
////   the 0x7fe of a lingering cast of a method the client keeps, `node_off`; a Normal
////   cast the client destroys with the 0x811), so the buff that stands for the stealth
////   never outlives it. A node that leaves the caster takes its cast's sources
////   with it (`effects_ended`), `damage_taken` ends the sources damage breaks, and
////   death and leaving drop all. Each input (a press, a timer, a go, the player's death,
////   a blow) compares the stealth before and after and ends with one `StealthChanged`
////   when it moved, so the connection's 0x8f5 follows the 0x811 and 0x7fe it causes and
////   precedes the procs it fires. A
////   caster's type 116 prerequisite reads the stealth as it stood before the go's own
////   effects, as every gate does (`subject_of`).
//// - **A player's procs** are the Proc rows (effect type 14, `spell_plan.ProcRow`) its casts hold on
////   it, by cast id and effect id (`State.procs`), each with the times it fired at. A go lists each
////   Proc row of its phase whose gate passes in the caster's target info and holds the caster's node
////   until the row's life ends, as a Stealth row does (`Spell4Effects.effectType.14.lifetime`), and
////   adds its source; a source leaves where a stealth source leaves (`effects_ended`), at the
////   caster's death but for the innate passive's, and at leaving. Each input ends in `settled`,
////   which records its events as pending (`State.pending`), in order: the input's own (`Died` for
////   `died`, `LeftCombat` for `combat_left`, and the hits of the strike round a go or a tick
////   settles, `hit_events`), a `LandsHeal` for each Heal change its effects start on the caster,
////   and its stealth change (`EnteredStealth` or `LeftStealth`). A hit is an event for each
////   damage description that landed on a creature: `LandsHit`, `LandsMeleeHit` when the spell is of
////   school 1, `LandsCritical` for a critical and `Kills` for a kill (a guess:
////   `Spell4Effects.effectType.14.client_evaluation`); a spell that only selects a unit raises none.
////   The rule decides nothing about a draw: the connection asks `proc_draws_needed` how many
////   chance words and gate rolls the pending events need, one draw for all, and hands them to
////   `procs_fire`, which matches each event, in order and then source order, against the proc rows
////   held when the input's own work was done (the server's choice, `.dataBits00.217_218`, `.0_44`):
////   a proc whose node the same input took off does not fire, and one the input applied does.
////   `proc.decide` checks, in this order, the limit (at most `count` fires in any `window_ms`, a
////   fire exactly `window_ms` after the last allowed, the server's choice of the edge,
////   `Spell4Effects.effectType.14.limits`), the filter, the holder gate, the event gate and the
////   chance (a word's fraction below the chance fires; a chance of 1.0 takes no word). A fire is
////   counted at the event; a proc with a delay starts a timer (`Due.ProcDue`) that casts the
////   spell when it fires, and the holder's cast ending cancels the timers of its procs. The cast
////   starts as a child's does, from the caster at its aim (`.dataBits03`): a 0x7ff with the holder's
////   spell as root and parent and no 0x7fd (`opcode.0x7ff.root_parent`). Its go and finish are
////   inputs of their own, so a fire's events are matched in a later step and no proc cascades inside
////   one. A spell whose caster condition refuses the caster's life (row 1, mask 225, refuses a dead
////   caster: `Spell4.spell4ConditionsIdCaster`, `cast.dead_player`) does not fire and records no
////   fire, with a debug line. A death leaves the passive's procs with the passive and ends every
////   other cast before the procs are matched, so a `Died` proc of any other cast is never held: its
////   go writes a debug line (the plan cannot tell the passive, so the rule enforces it,
////   `procs_held`); a camp drops the procs and their fire times.
//// - **A cast that lingers** is one whose last go has gone while a node of it still
////   has life: every step of its end runs (the current cast cleared, a channel's
////   cooldown, a stage's threshold closed) and only its 0x7fe waits, since the client
////   ends no buff on time (`cast.target_node_end`). A timer of the rule ends the
////   nodes as their time runs out, 0x811 for the units whose node ends and the 0x7fe
////   with the last. A lingering cast holds its id until then. A live cast's nodes end
////   on the same timer, 0x811 for the unit while the cast goes on, and a 0x801 stops a
////   cast the same way: its pending gos are cancelled and it lingers if a node has life
////   left, since a cancel ends no buff.
//// - **Persistence** is the server's alone: the client never evaluates
////   prerequisiteIdCasterPersistence or prerequisiteIdTargetPersistence, which it keeps
////   to word the results 282 and 283 (`Spell4.prerequisiteIdCasterPersistence`,
////   `0x1405648a0`). The connection calls `persisted` at the end of each input of a player
////   in the world, which is exact and needs no timer or interval (the tables give none).
////   Each live or lingering cast, lowest id first, whose spell's condition fails ends
////   (checked again after each end, since one can break another's): 0x7f9 {cast id, 282 or
////   283, the caster, 0}, which destroys the nodes the cast holds so its buff goes and leaves
////   the cast filed, then the 0x7fe that takes it out of the client's table, told to the
////   audience as a finish (`opcode.0x7f9`, `cast.target_node_end`; which message retail sent
////   is not known). The cast's go, finish and NodesEnd timers are cancelled, its property
////   modifiers and cooldown effects end, its stealth sources drop (the input's last effect
////   is `StealthChanged`), the current cast clears when it was this one, an open threshold
////   it is the base cast of closes as a 0x801 closes it, and a press held for the clear
////   starts. CasterPersistence (282) is checked before TargetPersistence (283), the caster
////   the first unit and the cast's primary target the second; TargetPersistence is checked
////   only for a cast whose primary target is the caster, since the connection holds no
////   creature's state. A condition of a type not read, a roll and a creature target keep the
////   cast, with one debug line for the spell.
//// - **A unit that leaves the caster's sight** takes its nodes with it on the client
////   (`0x1404550d0`), so the rule drops them too and a lingering cast left with no node
////   ends with its 0x7fe (`unit_removed`).
//// - **A go's rolls** are one for each type 37 condition among the gates of the
////   Proxies that start a child, of the gains that may be given and of the lasting
////   effects of the phase, and, for a row behind a target apply prerequisite, one set for
////   each unit the row reaches (`rolls_needed`); the connection draws that many from its
////   seed before it calls `went`, and none when there is no such condition, so no other
////   roll of the connection moves.
//// - **A child cast** is the Proxy's spell cast as its own, from the caster, with
////   root the pressed spell and parent the spell whose Proxy fired
////   (`opcode.0x7ff.root_parent`), after the Proxy's delay from the parent's go;
////   its 0x7ff goes to the caster too. Its go and finish follow as a pressed
////   cast's, and it starts no global cooldown (kind 3). A Proxy behind a caster
////   apply prerequisite or one its dataBits06 names starts only when each passes
////   against the caster at the go (`proxy_gates`). One behind a target apply
////   prerequisite as well starts a child on a unit only when that prerequisite passes
////   too, for each unit separately (`children`, `target_gate`): the target first and
////   the caster second (`Spell4Effects.prerequisiteIdTargetApply`), the struck unit as
////   the caster's picture shows it when the round closes (`went`'s `poses`; a unit it no
////   longer shows decides nothing and leaves a debug line), or the caster on its own
////   point for a Proxy aimed at it. The target gate takes no roll. A child's timer is
////   its own: the parent's finish
////   leaves the pending children, which start 100 ms after it (Crush), and only
////   the player leaving the world cancels them.
//// - **A RapidTap threshold** opens with the first tap's 0x816 and lasts the
////   ability's thresholdTime from a timer the server mirrors, since the client
////   closes it by itself then (`opcode.0x816`). Each later tap casts the stage at
////   the threshold's index, with root the ability and parent the ability
////   (`cast.stage_root_parent`), and the next index goes in 0x817; the last stage
////   closes the threshold with 0x814 and the bit set, which starts the ability's
////   cooldown. The window ending closes it, writes nothing and starts the cooldown
////   (`opcode.0x814`, `opcode.0x817`, `0x1403bfd60`).
//// - **A ChargeRelease threshold** opens with the first press's 0x816; the press's
////   cast, the base cast, stays live with no go until the release or a cancel
////   (`cast.charge_release_base`). Each later row's thresholdDuration after the
////   one before, a timer sends the next level in 0x817. The release is the next
////   press, which casts the row at the level reached; its first go starts the
////   ability's cooldown, and after its finish 0x814 closes the threshold and the
////   base cast ends with 0x7fe. The client marks the charge full at the ability's
////   thresholdTime and sends nothing, so the server holds the charge until a
////   release or a cancel.
//// - **The cancel** is 0x801: the server's cast id, a reason and a bit, which the
////   client sends as (6 or 11, 1) when the player's cast ends in its client, and
////   (0, 0) with the 0x816 value for an open ChargeRelease threshold
////   (`opcode.0x801`). It clears the caster's current cast, whatever cast that is,
////   and the cast ends with its go timers cancelled and 0x7fe to the caster and the
////   audience, no strike; the base cast of a charge ends its threshold too, with
////   0x814 before its 0x7fe. A cast that is not live is a debug line. Any other
////   reason or bit is one the client never sends, and ends the connection.
//// - **The audience** of a cast is the caster's viewers when it starts; its go and
////   finish go to them. A viewer writes a 0x7ff only when its client shows the
////   caster, and a go, or a finish, only for a cast it wrote
////   (genesis_prime/game/connection). The threshold messages go to the caster only.
//// - **Timers** are the connection's: this rule starts them with ids from
////   `first_timer`, one for each go, finish, child, held press, threshold window
////   and charge level waiting, and owns the ids from there up (`owns`).
////
//// - **The innate passive** is a cast the client never makes: `passive_started` starts it
////   at each join with a 0x7ff and no 0x7fd, as `Passive`, which starts no global
////   cooldown, is never the current cast, opens no threshold and runs no check of the
////   caster. Its go runs as any cast's, and the cast lingers with no 0x7fe, even when
////   no node of it lives, for the whole stay. The three passives hold caster condition
////   row 4 (mask 0: alive or dead) and propertyFlags 0x100 (the cast stays when its
////   caster is removed), so a death leaves it with its nodes and modifiers
////   (`Class.spell4IdInnateAbilityPassive00`, `Spell4.spell4ConditionsIdCaster`;
////   the server's choice for what death does to a cast no press made), and a camp, which
////   leaves every cast, drops it, so the next join starts it again.
////
//// What happens at each failure point of a cast:
////
//// | Point | What happens |
//// |---|---|
//// | a 0x9a body the client's reader refuses, or a cast id of 0 | the connection ends, nothing written |
//// | a 0x4db body the client's reader refuses | the connection ends, nothing written |
//// | a 0x4db whose bag index holds no ability | 0x7fc {0, 0, 4} for held 1, a debug line for held 0 |
//// | a 0x4db held 1 of the ability already held | the same hold: nothing written |
//// | a held cast refused, at the first press or a repeat | the 0x7fc, and the hold ends |
//// | the repeat timer fires after the release | nothing: the release cancelled it, and a firing that was already sent finds no hold |
//// | a press whose bag index the player does not hold | 0x7fc {client id, 0, 4} |
//// | a press past the last stage of an open threshold | 0x7fc {client id, the ability, 4} |
//// | a refusal of the client's own checks | 0x7fc with the result; nothing else changes |
//// | a spell whose cost has an EMM id the server does not read | 0x7fc with the cost's result, a warning once for the spell on the connection; nothing is paid |
//// | a cast with a cost ends before its first go: a 0x801, the caster's death or leaving | nothing is paid and nothing is sent for the cost; its reservation ends with the cast |
//// | a press needs points that a live cast has reserved | 0x7fc with the cost's result, as for a slot that holds too little |
//// | a threshold row's class cost of a vital the class's slots hold nothing of (a Charged Shot release at 0 Spell Power) | 0x7fc with 175; nothing is paid |
//// | the slot holds less than a live cast reserved when its first go comes (the Esper's empty, the Warrior's drain) | the go pays what the slot holds, down to 0 |
//// | a 0x801 ends a cast while the round of its first go is open | the cost was paid as the strike began; the round's answer finds no live cast: no go is written, the hits stand |
//// | a press whose CasterCast or TargetCast fails | 0x7fc {client id, spell, 151 or 281}, after every other check; nothing else changes |
//// | a press whose cast condition is of a type the server does not read | 0x7fc 151 or 281, a warning once for the spell |
//// | a held press, or a held key's repeat, whose cast condition fails when it starts | 0x7fc {client id, or 0 for a key, spell, 151}; nothing started, a key's hold ends |
//// | a caster requirement fails and the spell's waiver passes | the requirement is waived; the next is checked |
//// | a caster requirement fails and its waiver is not read | 0x7fc with the requirement's result, a warning once for the spell |
//// | a lasting cast's persistence fails | 0x7f9 {cast id, 282 or 283, caster, 0}, 0x7fe, CastFinished to each viewer; timers and modifiers end; the current cast clears; a press held for it starts |
//// | a persistence not read, or a target persistence on a creature | the cast goes on; a debug line once for the spell |
//// | two casts whose persistence fails in one input, or one that fails because the other ended | both end in that input, the lower cast id first |
//// | a persistence check while the player is leaving or dead | nothing: `left` and `died` have already dropped every cast |
//// | a press while one is held | 0x7fc 13 |
//// | a press of a spell whose caster conditions mask Ability Restriction while the caster holds it | 0x7fc 302, ahead of the cooldowns; a spell whose mask lacks bit 27 passes |
//// | a go gives the caster Ability Restriction | 0x87f to the caster and its audience, once for the effect; a `RestrictionEnd` timer at the row's delay plus duration, none for flag 2; the cast lingers until its persistence ends (the server reads no ride, so the hoverboard's ends in the go's own input: gap, #336) |
//// | a `RestrictionEnd` fires for a state the caster holds | 0x880 with the cast and the instance id of its 0x87f, before the cast's node ends; a row of duration 0 without flag 2 ends in the go's own step |
//// | a cast that holds Ability Restriction ends (its persistence fails, a type 80 removal takes its node off, its node ends by time) | the `RestrictionEnd` timers cancelled, and 0x880 for a state the row's end has not already ended, after the 0x7f9 or the 0x811; a death or a leave drops the state and writes nothing |
//// | a 0x805 result 3 of an activate cast of castMethod 5 | nothing: the interaction only began |
//// | a 0x805 result 1 before or after the cast time has run | the go and the finish at the later of the two: at the answer, or at the go's timer when the answer came first |
//// | a 0x805 result 0 or 2 | 0x7f9 146, 0x7fe, the go's timer cancelled; no go and no `Activated` |
//// | a 0x805 for a cast that is not live (the client's 0 as a finish closes its window) | nothing; a debug line |
//// | a 0x805 for a live cast that waits for no answer, naming another spell, or with a result of 4 to 7 | the connection ends |
//// | a go lists a heal while the caster's vital is full | the description carries the whole amount as its overheal; the vital writes nothing (genesis_prime/game/player_life) |
//// | a heal's timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing lands |
//// | a heal's start and its node's end fire in either order | the heal lands once, in the step of whichever is delivered first |
//// | a go lists an absorb and its connection restarts before the start | no pool: the connection enters with none and the client is created again |
//// | an absorb's start timer fires after its cast's node was taken off, the caster died or its persistence ended | no timer: it was cancelled with the node; nothing starts |
//// | an absorb's end timer fires after the pool was used up, or the death dropped it | the end writes nothing (genesis_prime/game/player_life) |
//// | a go of the cast arms its absorb while the earlier go's pool is held | the pool is refilled to the new amount, its end timer set again |
//// | an absorb's end and a blow reach the connection in one millisecond | arrival order: the pool soaks and then ends, or ends first |
//// | a go adds a Stealth source while the stack cap of its spell takes the first cast off | one source left, one 0x811, no `StealthChanged` |
//// | a go of a spell that ends stealth after the stealth ended | nothing to end, nothing written |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` after one of its goes and before its last | the other casts' stealth ends as the cast stops, the 0x811 and the change after the cast's own end |
//// | a 0x801 ends a cast of `EndsStealthAfterLastGo` before its first go | the stealth stays held, nothing written |
//// | the caster dies stealthed | every cast ends, the sources drop, `StealthChanged` last |
//// | the player leaves stealthed | the sources drop, nothing is written |
//// | a proc's trigger happens inside its window | nothing is cast, no fire is recorded |
//// | a proc's chance word is not below its chance | nothing is cast, no fire is recorded |
//// | a go's hit names a creature with no damage description | no event, no proc fires |
//// | a hit's trigger is matched while its proc's delay runs | the fire is counted at the event; the cast starts when its `ProcDue` timer fires, and is cancelled with the holder's cast |
//// | a proc's trigger and the removal of its holder's node in one input | the removed proc does not fire: procs are matched after the input's work |
//// | a proc's trigger happens for a caster its spell's condition refuses (a dead caster) | a debug line naming the row and the spell, no cast and no fire recorded |
//// | a go of a cast that is not the innate passive applies a `Died` proc | the proc is not held, with a debug line: a death ends the cast before it could fire |
//// | the caster dies in combat | `combat_left`, then `died`: 63366 twice, each under its own limit |
//// | the caster camps or leaves stealthed | the procs drop with every cast, nothing is cast or written |
//// | a press with 500 ms or less of the current cast left | held, nothing written; taken at the go or finish that clears the current cast |
//// | a 0x801 for a cast that is not live, or one already finished | no change, a debug line |
//// | a 0x801 (0, 0) naming no open threshold | no change, a debug line |
//// | a 0x801 with a reason and bit the client never sends | the connection ends |
//// | a parent cast finishes with a child's timer pending | the child starts when its timer fires, with the root and parent it was made with |
//// | a threshold's window ends with taps left | the threshold closes, nothing is written, the cooldown starts |
//// | the player camps with casts, children or a threshold pending | every timer is cancelled and nothing is written: the viewers' clients drop the cast with the unit (the connection writes each viewer's 0x7fe before its 0x355) |
//// | the caster's connection ends, a key held | its timers and the hold end with it; the map's `Gone` removes the unit from each viewer, which finishes its casts first |
//// | the caster dies with casts live | each ends with its timers cancelled and 0x7fe to the caster and its audience; the hold and every other timer end, but the innate passive's cast, its nodes, modifiers and pending children (`died`) |
//// | the innate passive's plan is missing | a warning and no cast: the plans hold every class's passive, or the load fails |
//// | a timer fires after its cast ended | a go finds no live cast and does nothing; the cast's end cancels its go timers |
//// | a timer fires in a status that holds no player in the world | dropped; the world is left already |
//// | the answer of a store ask comes after a timer's due time | the timer is taken after the answer: the go and finish are late by the ask, never lost |
//// | a viewer is told a go or finish of a cast it did not write | dropped (genesis_prime/game/connection) |
//// | the audience's connection has ended | the tell is dropped by the shell |
//// | a go lists a lasting effect, the last go leaves a node with life | the cast lingers with no 0x7fe; the timer of its earliest ending node starts |
//// | a lingering cast's timer fires with no node ended, or after a removal took the cast off | nothing is written; the timer starts again for the nodes left, or finds no cast |
//// | two nodes of a lingering cast end at the same time | one 0x811 naming both units |
//// | a removal and a lingering cast's timer in one step | the removal first; the timer finds nothing |
//// | the caster dies with a lingering cast | its 0x7fe to the caster and the audience, with the live casts' (server choice: the client has no death path) |
//// | the caster leaves with a lingering cast | every timer is cancelled and nothing is written; each viewer's 0x355 ends the cast on its client |
//// | the client cancels a cast that holds a node with life left | its pending gos are cancelled and it lingers, with no 0x7fe until the node ends |
//// | a live cast's node ends while the cast goes on | 0x811 for the unit; the cast's later gos go on |
//// | a unit holding a node of a cast leaves the caster's sight | the node is dropped with no frame; a lingering cast left with no node ends with its 0x7fe |

import genesis_prime/client_connection
import genesis_prime/game/activate
import genesis_prime/game/area
import genesis_prime/game/cast/cost as cast_cost
import genesis_prime/game/cast/frame as cast_frame
import genesis_prime/game/cast/gate as cast_gate
import genesis_prime/game/cast/heal as cast_heal
import genesis_prime/game/cast/state.{
  type Aimed, type AimedPress, type Applied, type Aside, type Caster,
  type CasterChange, type Due, type Effect, type Fact, type GateDecision,
  type HeldProc, type HeldRestriction, type Holder, type Interaction, type Issue,
  type Listed, type Live, type Message, type OnCreature, type Paid, type Refusal,
  type Resolution, type Restricting, type Role, type State, type StrikeGate,
  type Struck, type TargetVerdict, type Threshold, type TickAsked, type TickKey,
  type Ticking, type TickingOn, type Unbuilt, type UsedUnit, type Verdict,
  Absorb, Accept, Activated, Activating, Activation, Aimed, AimedPress,
  AnswerSucceeded, Answered, Applied, Aside, AwaitingAnswer, Base, CancelTimer,
  Cancelled, CannotTell, CastClears, Caster, CasterChangeEnding,
  CasterChangeEnds, CasterChangeStarts, CasterSide, ChargeLevel, Child,
  CooldownEnding, CooldownEnds, CooldownModifierEnds, CooldownModifierStarts,
  DamageTick, Deflected, DroppedControls, DroppedSignals, Finish,
  ForcedMoveStart, ForcedMoveStarts, Gain, GateFails, Go, GoAsked, Heal,
  HealTick, Healed, Held, HeldProc, HeldRestriction, Hit, HitCreature, HitPlayer,
  Hold, HoldForCast, Holding, Immune, ItemsIssue, KeyHeld, Lingering, Listed,
  Live, Log, Look, ModifierEnd, ModifierStart, NoClientCastId, NoInteraction,
  NoInteractionWaits, NoItemSpell, NodesEnd, NotBuilt, NotDecoded,
  NotSentByClient, OnCreature, Passive, Pay, PrerequisitesIssue, Pressed,
  PressedAt, ProcDue, Property, Refuse, RepeatHeld, Resolution, ResourceMoved,
  Restricting, RestrictionEnd, Send, Shortcut, ShortcutCast, SpellsIssue, Stage,
  StartChild, StartHeld, StartTimer, StartedMoving, Starts, State, StateEnd,
  StealthChanged, Strike, TargetChangeEnds, TargetChangeStarts,
  TargetModifierStart, Tell, Threshold, Tick, TickAsked, TickKey, TickStrike,
  Ticking, UnbuiltItemCharges, UnbuiltItemSpell, UnbuiltPlayerTarget,
  UnbuiltShortcut, UnbuiltSpell, Unheld, UnitSide, UnknownAnswer, UnknownCancel,
  Unpaid, UnreadItemPrerequisite, UnreadLinkPrerequisite, UnreadPrerequisite,
  UnreadShortcutPick, UnreadSpend, UntilRemovedIssue, UsedUnit, WindowEnd,
  WrongAnswerSpell,
} as cast_state
import genesis_prime/game/class_resource.{type Payment}
import genesis_prime/game/cooldown
import genesis_prime/game/crowd_control
import genesis_prime/game/damage
import genesis_prime/game/effect_kind
import genesis_prime/game/forced_move
import genesis_prime/game/hit
import genesis_prime/game/item_use
import genesis_prime/game/lasting
import genesis_prime/game/prerequisite
import genesis_prime/game/proc
import genesis_prime/game/shortcut_spell
import genesis_prime/game/spell_plan.{type Plans, type Proxy, type Spell}
import genesis_prime/game/start_place.{type Place}
import genesis_prime/game/strike_tell
import genesis_prime/game/ticking
import genesis_prime/game/unit_properties
import genesis_prime/message/ability_hold
import genesis_prime/message/cancel_cast.{type CancelCast}
import genesis_prime/message/cast_ability
import genesis_prime/message/cast_activate
import genesis_prime/message/cast_objective_ability
import genesis_prime/message/cast_result
import genesis_prime/message/client_activate_unit
import genesis_prime/message/client_side_interaction_result
import genesis_prime/message/combat_result
import genesis_prime/message/crowd_control_state.{type CrowdControlState}
import genesis_prime/message/interaction_result
import genesis_prime/message/item_place.{type ItemPlace}
import genesis_prime/message/item_use as item_use_message
import genesis_prime/message/spell_effect_tick.{
  type SpellEffectTick, SpellEffectTick,
}
import genesis_prime/message/spell_stack_removed.{SpellStackRemoved}
import genesis_prime/message/spell_targets_removed.{SpellTargetsRemoved}
import genesis_prime/step.{
  type ConnectionId, type Now, type TimerId, LogDebug, LogInfo, LogWarning,
}
import genesis_prime/table/id.{
  type Item2Id, type Spell4BaseId, type Spell4EffectsId, type Spell4Id,
  Spell4EffectsId,
}
import genesis_prime/world_map/map
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string

/// The caster's 0x9a, 0x4DB or 0x801, decoded and decided: the new state and what
/// the connection must do, or the refusal that ends the connection. `now` is the
/// time of the input; the plans give each ability's tree.
pub fn take(
  cast cast: State,
  message message: Message,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  case message {
    Pressed -> pressed(cast:, body:, caster:, plans:, now:)
    KeyHeld -> key_held(cast:, body:, caster:, plans:, now:)
    Cancelled ->
      cancelled(cast:, body:, caster:, now:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
    Answered ->
      answered(cast:, body:, caster:, now_ms:)
      |> result.map(fn(taken) { released(taken:, caster:, now_ms:) })
  }
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

/// The caster's 0x97, the right-click of a unit, decoded and decided: the client's cast
/// of the unit's activate spell (`opcode.0x97`). `target_of` says what the unit the
/// message names is to the caster's connection (its picture), and `caster_radius` is the
/// hit radius of the caster's own body, which the range check takes beside the target's.
/// The spell is the creature's pick (genesis_prime/game/activate `pick`); a cast that
/// cannot start is refused with the result the client names, and one that can runs as any
/// cast does, for the activate cast time (`activation_spell`), and its last go raises `Activated`.
pub fn activate(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  activation_pressed(
    cast:,
    body:,
    caster:,
    activations:,
    target_of:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

/// The caster's 0x943, the use of an item the client sends from StartItemUseCast
/// (`opcode.0x943`), decoded and decided: the client's cast of the item's spell at the unit
/// it names. `held_at` says which item the caster holds at a place, `check` is the client's
/// own checks of the item (genesis_prime/game/item_use `check`, given the target's
/// checklist index), `target_of` says what the unit the message names is to the caster's
/// connection, and `in_cast_group` whether the unit is in a TargetGroup (the spell's cast
/// group, which the client does not test). A use the client would not have sent ends the
/// connection; one it sends and refuses is refused with its result; one the server has no
/// plan for (the item's spell has no Activate effect) is refused as not built; the others
/// run as an activate cast does, and the go raises `Activated` for the unit.
pub fn use_item(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  held_at held_at: fn(ItemPlace) -> Option(Item2Id),
  check check: fn(
    Item2Id,
    ItemPlace,
    Option(Int),
    fn(Int) -> prerequisite.Verdict,
  ) -> Result(Spell4Id, item_use.Refusal),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  item_used(
    cast:,
    body:,
    caster:,
    held_at:,
    check:,
    activations:,
    target_of:,
    in_cast_group:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

fn item_used(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  held_at held_at: fn(ItemPlace) -> Option(Item2Id),
  check check: fn(
    Item2Id,
    ItemPlace,
    Option(Int),
    fn(Int) -> prerequisite.Verdict,
  ) -> Result(Spell4Id, item_use.Refusal),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    item_use_message.decode(body)
    |> client_connection.decoded(message_id: item_use_message.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let unit_id = press.target_unit_id
  let target = target_of(unit_id)
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case held_at(press.item) {
    None -> refusal(0, cast_result.ItemBad)
    Some(item) ->
      case
        check(
          item,
          press.second_item,
          // Another player's unit has no checklist index: the client's quest check reads
          // -1 for it (`0x140398cc0`).
          case target {
            activate.Usable(checklist_index:, ..) -> Some(checklist_index)
            activate.AnotherPlayer -> Some(-1)
            activate.Unseen -> None
          },
          activate.checker(activations:, subject: subject_of(cast:, caster:)),
        )
      {
        Error(item_use.NoItemSpell) -> Error(NoItemSpell)
        Error(item_use.NotSentByClient) -> Error(NotSentByClient)
        Error(item_use.Declined(spell4_id:, result:)) ->
          refusal(spell4_id.value, result)
        Error(item_use.Charged(spell4_id:, max_charges:)) ->
          not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: spell4_id.value,
            key: UnbuiltItemCharges(item_id: item.value),
            result: cast_result.IllegalSpellCast,
            why: "(Item2 "
              <> int.to_string(item.value)
              <> ") has maxCharges "
              <> int.to_string(max_charges)
              <> ", which the server does not hold: the client refuses an item with no charges left with 25",
            issue: ItemsIssue,
          )
        Error(item_use.UnreadPrerequisite(spell4_id:, prerequisite_type:)) ->
          not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: spell4_id.value,
            key: UnreadItemPrerequisite(prerequisite_type:),
            result: cast_result.IllegalSpellCast,
            why: "is gated by a prerequisite of the type "
              <> int.to_string(prerequisite_type)
              <> ", which the server does not read",
            issue: PrerequisitesIssue,
          )
        Ok(spell4_id) ->
          item_spell_cast(
            cast:,
            caster:,
            caster_radius:,
            now_ms:,
            client_cast_id:,
            unit_id:,
            target:,
            activations:,
            in_cast_group:,
            spell4_id: spell4_id.value,
          )
      }
  }
}

/// The cast of an item's spell, which the item's checks let through, at the unit the
/// press names (`item_used`): refused as not built when the spell has no Activate effect,
/// refused 91 for a unit not shown and 100 for another player. At a creature the target's
/// life and states come first (`target_state_refusal`), then 89 for a unit the spell's cast
/// group refuses (`activate.passes_cast_group`), else the activate cast of the unit, which
/// refuses by range (`0x1403b2240` tests in that order).
fn item_spell_cast(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  target target: activate.Target,
  activations activations: activate.Activations,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  spell4_id spell4_id: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case activate.planned_of(activations:, spell4_id:) {
    Error(Nil) ->
      not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltItemSpell(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "has no Activate effect, which is all the server counts an item's use through",
        issue: ItemsIssue,
      )
    Ok(activate.NoSpell4Row) -> refusal(spell4_id, cast_result.SpellUnknown)
    Ok(activate.CannotBePlanned(why:)) ->
      not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltItemSpell(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "cannot be planned: " <> why,
        issue: SpellsIssue,
      )
    Ok(activate.Planned(
      spell:,
      effects:,
      dropped_signals:,
      limits:,
      cast_group_id:,
    )) ->
      // A creature's `withheld` and `ClosedLink` are what the client's interact menu does
      // not offer; an item's use never goes through that menu, and a closed link only
      // gates the objectives `by_item` leaves uncounted.
      case target {
        activate.Unseen -> refusal(spell4_id, cast_result.NoTarget)
        activate.AnotherPlayer ->
          refusal(spell4_id, cast_result.TargetIsNotUseable)
        activate.Usable(
          creature_id:,
          creature:,
          checklist_index:,
          body: unit,
          alive:,
          held:,
          ..,
        ) ->
          case target_state_refusal(spell:, alive:, held:) {
            Some(result) -> refusal(spell4_id, result)
            None ->
              case
                item_cast_group(
                  cast:,
                  caster:,
                  client_cast_id:,
                  unit_id:,
                  spell4_id:,
                  cast_group_id:,
                  creature:,
                  checklist_index:,
                  activations:,
                  in_cast_group:,
                )
              {
                Error(taken) -> taken
                Ok(Nil) ->
                  activation_reached(
                    cast:,
                    caster:,
                    caster_radius:,
                    now_ms:,
                    client_cast_id:,
                    unit_id:,
                    creature_id:,
                    creature:,
                    target: unit,
                    alive:,
                    by_item: True,
                    spell:,
                    cast_time_ms: spell.cast_time_ms,
                    effects:,
                    dropped_signals:,
                    limits:,
                  )
              }
          }
      }
  }
}

/// The client's cast-group check of an item's spell at a creature (`activate.passes_cast_group`):
/// `Ok` when the cast goes on, else the answer to the press.
fn item_cast_group(
  cast cast: State,
  caster caster: Caster,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  activations activations: activate.Activations,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> Result(Nil, Result(#(State, List(Effect)), Refusal)) {
  case
    cast_group_of(
      cast:,
      caster:,
      activations:,
      unit_id:,
      spell4_id:,
      cast_group_id:,
      creature:,
      checklist_index:,
      in_cast_group:,
    )
  {
    activate.InCastGroup -> Ok(Nil)
    activate.OutsideCastGroup ->
      Error(
        Ok(
          #(cast, [
            cast_frame.refused(
              client_cast_id:,
              spell4_id:,
              result: cast_result.TargetGroup,
            ),
          ]),
        ),
      )
    activate.CastGroupUnread(prerequisite_type:) ->
      Error(not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnreadPrerequisite(prerequisite_type:),
        result: cast_result.IllegalSpellCast,
        why: "of a creature activates through a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
        issue: PrerequisitesIssue,
      ))
  }
}

/// The caster's 0x9d, the press of the button a type 11 objective gave it (`opcode.0x9d`),
/// decoded and decided. A spell the caster holds no button for is refused with result 1
/// (`UnableToCreateSpell`), as the client refuses a press of a shortcut it does not hold
/// (`0x14039b340`); one of the self-aimed spells the objectives name casts on the caster
/// as any cast does, and its first go raises `ShortcutCast`. A spell that takes a unit
/// (targetType 1, 3, 5 or 8) is checked against the unit the press names in the order the
/// client checks it (`aimed_shortcut`) and starts on that unit; its first go raises
/// `ShortcutCast` with the unit. `target_of` says what a unit the press names is,
/// `in_cast_group` whether a unit is in a TargetGroup, and `activations` hold the
/// creatures' activate picks, which a cast group reads.
pub fn shortcut(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  held held: Set(Int),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  let now_ms = now.monotonic_ms
  shortcut_pressed(
    cast:,
    body:,
    caster:,
    shortcuts:,
    held:,
    activations:,
    target_of:,
    in_cast_group:,
    caster_radius:,
    now_ms:,
  )
  |> result.map(fn(taken) { continued(taken:, caster:, now_ms:) })
  |> result.map(fn(taken) { settled(cast:, own: [], step: fn() { taken }) })
}

fn shortcut_pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  shortcuts shortcuts: shortcut_spell.Shortcuts,
  held held: Set(Int),
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_objective_ability.decode(body)
    |> client_connection.decoded(message_id: cast_objective_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let spell4_id = press.spell4_id
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  use <- bool.guard(
    when: !set.contains(held, spell4_id),
    return: refusal(cast_result.UnableToCreateSpell),
  )
  case shortcut_spell.planned_of(shortcuts:, spell4_id:) {
    Error(Nil) | Ok(shortcut_spell.NoSpell4Row) ->
      refusal(cast_result.SpellUnknown)
    Ok(shortcut_spell.CannotBePlanned(why:)) ->
      not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: UnbuiltShortcut(spell4_id:),
        result: cast_result.IllegalSpellCast,
        why: "cannot be planned: " <> why,
        issue: SpellsIssue,
      )
    Ok(shortcut_spell.Planned(spell:)) ->
      accepted_and_started(
        cast:,
        caster:,
        now_ms:,
        client_cast_id:,
        spell: shortcut_spell_of(spell:),
        primary_target: caster.unit_id,
        role: Shortcut(interaction: interaction_of(spell:), aimed: None),
        target_subject: None,
        dropping: fn(cast) { #(cast, []) },
      )
    Ok(shortcut_spell.Aimed(spell:, aim:)) ->
      aimed_shortcut(
        cast:,
        caster:,
        caster_radius:,
        now_ms:,
        client_cast_id:,
        unit_id: press.target_unit_id,
        spell:,
        aim:,
        activations:,
        target_of:,
        in_cast_group:,
      )
  }
}

fn issue_name(issue issue: Issue) -> String {
  case issue {
    ItemsIssue ->
      "Items, equipment, vendors, levels and currency work on the real client (#333)"
    PrerequisitesIssue ->
      "Quests, zones and prerequisites work on the real client (#334)"
    SpellsIssue -> "Spells work in depth on the real client (#336)"
    UntilRemovedIssue ->
      "A crowd-control state that lasts until removed ends when its spell ends (#803)"
  }
}

/// The plan's spell as a quest button's cast casts it: a castMethod 5 spell waits for the
/// client's answer without a cast time of its own, any other as planned.
fn shortcut_spell_of(spell spell: Spell) -> Spell {
  case interaction_of(spell:) {
    AwaitingAnswer -> activation_spell(spell:, cast_time_ms: 0)
    NoInteraction | AnswerSucceeded -> spell
  }
}

/// A press of a quest button's spell that takes a unit, at the unit the press names,
/// refused in the order the client's checks give (`0x1403ae8c0`, `0x1403b2240`,
/// `0x1403b44b0`): 91 for no unit or one the picture does not show; 32 for the caster
/// itself; 106 or 107 and 108 for the unit's life and combat; 102 for a player the spell
/// refuses (answered first for a player, whose life and combat are not held); 89 for a
/// unit outside the spell's cast group; the result of the first crowd-control state the
/// unit holds that the spell's target row masks (122 for Stun, and so on); the range's
/// 104, 105 or 183, measured with the spell's own limits; then the spell's CasterCast and TargetCast (151, 281), read as
/// any cast's with the unit as the TargetCast's first unit. Then started on
/// the unit. A player or the caster itself reaches the client's player faction test, which
/// the server does not build, and another player's life and combat are not held: those
/// are refused 285 as not built. The target states the server does not hold (96
/// invulnerable, 140 zone, 98 vital, 92 immunity) are not checked: a gap in the issue
/// "Spells work in depth on the real client: cast times, telegraphs, buffs, crowd control
/// and ticking effects".
fn aimed_shortcut(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  spell spell: Spell,
  aim aim: shortcut_spell.Aim,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  let press =
    AimedPress(
      cast:,
      caster:,
      caster_radius:,
      now_ms:,
      client_cast_id:,
      unit_id:,
      spell:,
      aim:,
      activations:,
      in_cast_group:,
      held: [],
    )
  case unit_id == caster.unit_id, target_of(unit_id) {
    True, _ -> aimed_at_the_caster(press:)
    False, activate.Unseen ->
      press_refused(press:, result: cast_result.NoTarget)
    False, activate.AnotherPlayer -> aimed_at_a_player(press:)
    False,
      activate.Usable(
        creature_id:,
        creature:,
        checklist_index:,
        body:,
        alive:,
        in_combat:,
        held:,
        ..,
      )
    ->
      aimed_at_a_creature(
        press: AimedPress(..press, held:),
        creature_id:,
        creature:,
        checklist_index:,
        target_body: body,
        alive:,
        in_combat:,
      )
  }
}

fn press_refused(
  press press: AimedPress,
  result result: cast_result.CastResult,
) -> Result(#(State, List(Effect)), Refusal) {
  Ok(
    #(press.cast, [
      cast_frame.refused(
        client_cast_id: press.client_cast_id,
        spell4_id: press.spell.spell4_id.value,
        result:,
      ),
    ]),
  )
}

fn press_unbuilt(
  press press: AimedPress,
  key key: Unbuilt,
  why why: String,
) -> Result(#(State, List(Effect)), Refusal) {
  not_built_refusal(
    cast: press.cast,
    client_cast_id: press.client_cast_id,
    spell4_id: press.spell.spell4_id.value,
    key:,
    result: cast_result.IllegalSpellCast,
    why:,
    issue: PrerequisitesIssue,
  )
}

fn press_at_player_unbuilt(
  press press: AimedPress,
  why why: String,
) -> Result(#(State, List(Effect)), Refusal) {
  press_unbuilt(
    press:,
    key: UnbuiltPlayerTarget(spell4_id: press.spell.spell4_id.value),
    why:,
  )
}

/// The caster itself: refused 32 unless the spell's flags let it be its own primary
/// target, and then it reaches the client's player faction test, which is not built.
fn aimed_at_the_caster(
  press press: AimedPress,
) -> Result(#(State, List(Effect)), Refusal) {
  case spell_plan.has_flag(flags: press.aim.mechanics_flags, bit: 2) {
    False ->
      press_refused(press:, result: cast_result.CasterCannotBePrimaryTarget)
    True ->
      press_at_player_unbuilt(
        press:,
        why: "names the caster itself, which the client's player faction test judges",
      )
  }
}

/// Another player's unit: a spell that refuses a player refuses every player (the
/// client's 106, 108 and 102 all refuse, and the connection holds no player's life or
/// combat to tell which); a spell that tests life or combat, or reaches the player
/// faction test, is not built.
fn aimed_at_a_player(
  press press: AimedPress,
) -> Result(#(State, List(Effect)), Refusal) {
  let tests_life_or_combat =
    press.spell.target_death != spell_plan.AliveOrDead
    || press.aim.target_combat == shortcut_spell.OutOfCombatOnly
  case
    spell_plan.has_flag(flags: press.aim.valid_targets, bit: 1),
    tests_life_or_combat
  {
    True, _ -> press_refused(press:, result: cast_result.TargetCannotBePlayer)
    False, True ->
      press_at_player_unbuilt(
        press:,
        why: "names another player, whose life and combat the connection does not hold",
      )
    False, False ->
      case press.aim.cast_group_id {
        0 ->
          press_at_player_unbuilt(
            press:,
            why: "names another player, who reaches the client's player faction test",
          )
        _ ->
          press_at_player_unbuilt(
            press:,
            why: "names another player and a cast group, which tests a player by its faction and race",
          )
      }
  }
}

/// A creature or object: life, then combat, then the states it holds, then cast group and
/// range, then the spell's own conditions and the start.
fn aimed_at_a_creature(
  press press: AimedPress,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  case life_and_combat_refusal(press:, alive:, in_combat:) {
    Some(result) -> press_refused(press:, result:)
    None -> {
      use <- target_held(press:)
      aimed_in_group(
        press:,
        creature_id:,
        creature:,
        checklist_index:,
        target_body:,
        alive:,
        in_combat:,
      )
    }
  }
}

/// The client's 106 and 107 for the target's life, then its 108 for combat.
fn life_and_combat_refusal(
  press press: AimedPress,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Option(cast_result.CastResult) {
  case press.spell.target_death, alive {
    spell_plan.CannotBeDead, False -> Some(cast_result.TargetCannotBeDead)
    spell_plan.MustBeDead, True -> Some(cast_result.TargetMustBeDead)
    spell_plan.CannotBeDead, True
    | spell_plan.MustBeDead, False
    | spell_plan.AliveOrDead, _
    ->
      case press.aim.target_combat, in_combat {
        shortcut_spell.OutOfCombatOnly, True ->
          Some(cast_result.TargetCannotBeInCombat)
        shortcut_spell.OutOfCombatOnly, False
        | shortcut_spell.CombatAllowed, _
        -> None
      }
  }
}

fn aimed_in_group(
  press press: AimedPress,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  case
    cast_group_of(
      cast: press.cast,
      caster: press.caster,
      activations: press.activations,
      unit_id: press.unit_id,
      spell4_id: press.spell.spell4_id.value,
      cast_group_id: press.aim.cast_group_id,
      creature:,
      checklist_index:,
      in_cast_group: press.in_cast_group,
    )
  {
    activate.InCastGroup ->
      aimed_in_range(press:, creature_id:, target_body:, alive:, in_combat:)
    activate.OutsideCastGroup ->
      press_refused(press:, result: cast_result.TargetGroup)
    activate.CastGroupUnread(prerequisite_type:) ->
      press_unbuilt(
        press:,
        key: UnreadShortcutPick(prerequisite_type:),
        why: "names a creature whose activate pick rests on a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
      )
  }
}

/// The client's cast-group check of a cast of `spell4_id` at the creature `unit_id`: the
/// creature's activate pick for the caster, read as `activate.passes_cast_group` needs it.
fn cast_group_of(
  cast cast: State,
  caster caster: Caster,
  activations activations: activate.Activations,
  unit_id unit_id: Int,
  spell4_id spell4_id: Int,
  cast_group_id cast_group_id: Int,
  creature creature: activate.Creature,
  checklist_index checklist_index: Int,
  in_cast_group in_cast_group: fn(Int, Int) -> Bool,
) -> activate.CastGroup {
  activate.passes_cast_group(
    spell4_id:,
    cast_group_id:,
    creature:,
    picked: activate.pick(
      creature:,
      default_spell: activations.default_spell,
      check: activate.checker(
        activations:,
        subject: subject_for_use(cast:, caster:, unit_id:, checklist_index:),
      ),
    ),
    in_cast_group: in_cast_group(_, unit_id),
  )
}

/// The client's crowd-control check of the target (`0x1403b2240`): a state the unit holds
/// that the spell's target mask names refuses the press with that state's target result,
/// after the target's life and combat and before the cast group and the range.
fn target_held(
  press press: AimedPress,
  otherwise otherwise: fn() -> Result(#(State, List(Effect)), Refusal),
) -> Result(#(State, List(Effect)), Refusal) {
  case
    crowd_control.first_masked(
      mask: press.spell.target_cc_mask,
      held: press.held,
    )
  {
    Ok(state) ->
      press_refused(
        press:,
        result: cast_result.from_value(crowd_control.target_result(state:)),
      )
    Error(Nil) -> otherwise()
  }
}

fn aimed_in_range(
  press press: AimedPress,
  creature_id creature_id: Int,
  target_body target_body: activate.Body,
  alive alive: Bool,
  in_combat in_combat: Bool,
) -> Result(#(State, List(Effect)), Refusal) {
  case
    activate.range_of(
      limits: press.aim.limits,
      caster: activate.Body(
        place: press.caster.place,
        radius: press.caster_radius,
      ),
      target: target_body,
    )
  {
    activate.TooClose ->
      press_refused(press:, result: cast_result.TargetRangeMin)
    activate.TooFar -> press_refused(press:, result: cast_result.TargetRangeMax)
    activate.TooHigh ->
      press_refused(press:, result: cast_result.TargetRangeVertical)
    activate.Within ->
      accepted_and_started(
        cast: press.cast,
        caster: press.caster,
        now_ms: press.now_ms,
        client_cast_id: press.client_cast_id,
        spell: shortcut_spell_of(spell: press.spell),
        primary_target: press.unit_id,
        role: Shortcut(
          interaction: interaction_of(spell: press.spell),
          aimed: Some(PressedAt(unit_id: press.unit_id, alive_at_press: alive)),
        ),
        target_subject: Some(target_subject_of(
          cast: press.cast,
          caster: press.caster,
          unit_id: press.unit_id,
          creature_id:,
          in_combat:,
          place: target_body.place,
        )),
        dropping: fn(cast) { #(cast, []) },
      )
  }
}

/// The subject of the unit a press named, for the spell's TargetCast: what the caster's
/// live casts hold on it (a live cast whose primary target it is, and the nodes it holds
/// there), and the caster second. The unit is the creature of Creature2 row `creature_id`,
/// the first unit a type 38 condition of the TargetCast compares.
fn target_subject_of(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  in_combat in_combat: Bool,
  place place: Place,
) -> prerequisite.Subject {
  prerequisite.of_target(
    under: held_by_caster_on(cast:, caster:, unit_id:),
    caster_unit: caster.unit_id,
    in_combat:,
    target: area.pose_of(place:),
    caster: area.pose_of(place: caster.place),
    quests: caster.quests,
    creature_id:,
    checker: caster.checker,
  )
}

/// What the caster's casts hold on the unit `unit_id`: a live cast whose primary target it
/// is, and the nodes the caster's casts hold there, each with the caster as its caster.
fn held_by_caster_on(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
) -> List(lasting.Held) {
  dict.values(cast.casts)
  |> list.filter(fn(live) { live.primary_target == unit_id })
  |> list.map(fn(live) {
    lasting.Held(
      spell4_id: live.spell.spell4_id,
      caster: caster.unit_id,
      count: 0,
      groups: live.spell.groups,
    )
  })
  |> list.append(
    list.map(holds_on(cast:, unit_id:), fn(hold) {
      lasting.Held(
        spell4_id: hold.spell4_id,
        caster: caster.unit_id,
        count: hold.node.count,
        groups: hold.groups,
      )
    }),
  )
}

/// The subject of the prerequisites a use of a creature checks: the caster, with the
/// creature's unit as the second unit and its checklist index as the unit's 0x262
/// carried it, standing nowhere (type 108 reads no arc of a use). The activate pick and
/// the creature's link to an objective check their prerequisites for it.
pub fn subject_for_use(
  cast cast: State,
  caster caster: Caster,
  unit_id unit_id: Int,
  checklist_index checklist_index: Int,
) -> prerequisite.Subject {
  prerequisite.counting(
    subject: prerequisite.Subject(
      ..subject_of(cast:, caster:),
      second_unit: Some(unit_id),
      positions: prerequisite.NotPlaced,
    ),
    checklist_index:,
  )
}

/// The caster's 0xb3, the client's use of a unit whose creature has no activate spell
/// (`opcode.0xb3`, `0x14039d4a0`): no cast and no delay, so the use is `Activated` at
/// once. `unit_of` says what the unit the message names is, or `Error(Nil)` for a unit
/// that is no creature or object the caster's client shows. The client sends 0xb3 only
/// from its click of an offered interaction within reach (`0x14039d2c0`, range
/// `activate.use_limits`) and only when the creature's pick is spell 0 (`0x14039d510`),
/// so a dead creature, a unit out of reach, one the server does not offer, one whose pick is
/// a spell and one the server cannot pick for are logged and change nothing.
pub fn activate_unit(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  unit_of unit_of: fn(Int) -> Result(UsedUnit, Nil),
  caster_radius caster_radius: Float,
) -> Result(List(Effect), Refusal) {
  use used <- result.map(
    client_activate_unit.decode(body)
    |> client_connection.decoded(message_id: client_activate_unit.message_id)
    |> result.map_error(NotDecoded),
  )
  let unit_id = used.unit_id
  let declined = fn(why) {
    [
      Log(
        level: LogWarning,
        text: "the use of unit "
          <> int.to_string(unit_id)
          <> " (0xb3) "
          <> why
          <> ": it counts for nothing",
      ),
    ]
  }
  case unit_of(unit_id) {
    Error(Nil) -> declined("names no creature or object the client shows")
    Ok(UsedUnit(alive: False, ..)) ->
      declined("names a creature that is dead: its interaction is not offered")
    Ok(UsedUnit(link: activate.ClosedLink, ..)) ->
      declined(
        "names a creature whose link to an objective is closed: the client offers it nothing",
      )
    Ok(UsedUnit(link: activate.UnreadLink(prerequisite_type:), ..)) ->
      declined(
        "names a creature whose link to an objective rests on a prerequisite of the type "
        <> int.to_string(prerequisite_type)
        <> ", which the server does not read",
      )
    Ok(UsedUnit(
      creature_id:,
      creature:,
      checklist_index:,
      body: unit,
      offered:,
      link: activate.NoLink,
      ..,
    ))
    | Ok(UsedUnit(
        creature_id:,
        creature:,
        checklist_index:,
        body: unit,
        offered:,
        link: activate.OpenLink,
        ..,
      )) ->
      case
        activate.range_of(
          limits: activate.use_limits,
          caster: activate.Body(place: caster.place, radius: caster_radius),
          target: unit,
        ),
        offered
      {
        activate.Within, True -> {
          let subject =
            subject_for_use(cast:, caster:, unit_id:, checklist_index:)
          case
            activate.pick(
              creature:,
              default_spell: activations.default_spell,
              check: activate.checker(activations:, subject:),
            )
          {
            activate.NoActivateSpell -> [
              Activated(
                unit_id:,
                creature_id:,
                alive_at_press: True,
                by_item: False,
              ),
            ]
            activate.Picked(spell4_id:) ->
              declined(
                "names a creature whose activate spell is "
                <> int.to_string(spell4_id)
                <> ", which the client casts with 0x97",
              )
            activate.Unread(prerequisite_type:) ->
              declined(
                "names a creature that activates through a prerequisite of the type "
                <> int.to_string(prerequisite_type)
                <> ", which the server does not read",
              )
          }
        }
        activate.Within, False ->
          declined(
            "names a unit that is not offered: no open objective counts a use of it, or its bit is set",
          )
        activate.TooClose, _ | activate.TooFar, _ | activate.TooHigh, _ ->
          declined("names a unit out of the interaction range")
      }
  }
}

fn activation_pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  activations activations: activate.Activations,
  target_of target_of: fn(Int) -> activate.Target,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_activate.decode(body)
    |> client_connection.decoded(message_id: cast_activate.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  let client_cast_id = press.client_cast_id
  let refusal = fn(spell4_id, result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case target_of(press.target_unit_id) {
    activate.Unseen -> refusal(0, cast_result.CasterMustHaveTarget)
    activate.AnotherPlayer -> refusal(0, cast_result.NoTarget)
    activate.Usable(withheld: Some(withheld), ..) ->
      Ok(
        #(cast, [
          Log(
            level: LogWarning,
            text: "the activate cast of unit "
              <> int.to_string(press.target_unit_id)
              <> case withheld {
              activate.HostileToPlayer -> " names a unit hostile to the player"
              activate.InCombat -> " names a unit in combat"
            }
              <> ": the client offers it nothing, so it is refused with "
              <> int.to_string(cast_result.to_value(
              cast_result.TargetIsNotUseable,
            )),
          ),
          cast_frame.refused(
            client_cast_id:,
            spell4_id: 0,
            result: cast_result.TargetIsNotUseable,
          ),
        ]),
      )
    activate.Usable(link: activate.ClosedLink, ..) ->
      Ok(
        #(cast, [
          Log(
            level: LogWarning,
            text: "the activate cast of unit "
              <> int.to_string(press.target_unit_id)
              <> " names a creature whose link to an objective is closed: the client offers it nothing, so it is refused with "
              <> int.to_string(cast_result.to_value(
              cast_result.TargetIsNotUseable,
            )),
          ),
          cast_frame.refused(
            client_cast_id:,
            spell4_id: 0,
            result: cast_result.TargetIsNotUseable,
          ),
        ]),
      )
    activate.Usable(link: activate.UnreadLink(prerequisite_type:), ..) ->
      not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id: 0,
        key: UnreadLinkPrerequisite(prerequisite_type:),
        result: cast_result.IllegalSpellCast,
        why: "of a creature whose link to an objective rests on a prerequisite of the type "
          <> int.to_string(prerequisite_type)
          <> ", which the server does not read",
        issue: PrerequisitesIssue,
      )
    activate.Usable(
      creature_id:,
      creature:,
      checklist_index:,
      link: activate.NoLink,
      body: target,
      alive:,
      in_combat: _,
      held:,
      withheld: None,
    )
    | activate.Usable(
        creature_id:,
        creature:,
        checklist_index:,
        link: activate.OpenLink,
        body: target,
        alive:,
        in_combat: _,
        held:,
        withheld: None,
      ) -> {
      let subject =
        subject_for_use(
          cast:,
          caster:,
          unit_id: press.target_unit_id,
          checklist_index:,
        )
      let picked =
        activate.pick(
          creature:,
          default_spell: activations.default_spell,
          check: activate.checker(activations:, subject:),
        )
      case picked {
        activate.NoActivateSpell -> refusal(0, cast_result.TargetIsNotUseable)
        activate.Unread(prerequisite_type:) ->
          not_built_refusal(
            cast:,
            client_cast_id:,
            spell4_id: 0,
            key: UnreadPrerequisite(prerequisite_type:),
            result: cast_result.IllegalSpellCast,
            why: "of a creature activates through a prerequisite of the type "
              <> int.to_string(prerequisite_type)
              <> ", which the server does not read",
            issue: PrerequisitesIssue,
          )
        activate.Picked(spell4_id:) ->
          case activate.planned_of(activations:, spell4_id:) {
            Error(Nil) | Ok(activate.NoSpell4Row) ->
              refusal(spell4_id, cast_result.SpellUnknown)
            Ok(activate.CannotBePlanned(why:)) ->
              not_built_refusal(
                cast:,
                client_cast_id:,
                spell4_id:,
                key: UnbuiltSpell(spell4_id:),
                result: cast_result.IllegalSpellCast,
                why: "cannot be planned: " <> why,
                issue: SpellsIssue,
              )
            Ok(activate.Planned(spell:, effects:, dropped_signals:, limits:, ..)) ->
              activation_in_range(
                cast:,
                caster:,
                caster_radius:,
                now_ms:,
                client_cast_id:,
                unit_id: press.target_unit_id,
                creature_id:,
                creature:,
                target:,
                alive:,
                held:,
                by_item: False,
                spell:,
                cast_time_ms: activate.cast_time_for(
                  creature:,
                  spell4_id: spell.spell4_id.value,
                ),
                effects:,
                dropped_signals:,
                limits:,
              )
          }
      }
    }
  }
}

/// The result `0x1403b2240` gives first for an activate cast at a creature: 106 or 107 when
/// the target's life is not the one its Spell4 target row allows, then the target result of
/// the first state the creature holds that the spell's target mask names. `None` when the
/// target's life and states let the cast go on to its cast group and range.
fn target_state_refusal(
  spell spell: Spell,
  alive alive: Bool,
  held held: List(CrowdControlState),
) -> Option(cast_result.CastResult) {
  case spell.target_death, alive {
    spell_plan.CannotBeDead, False -> Some(cast_result.TargetCannotBeDead)
    spell_plan.MustBeDead, True -> Some(cast_result.TargetMustBeDead)
    spell_plan.CannotBeDead, True
    | spell_plan.MustBeDead, False
    | spell_plan.AliveOrDead, _
    ->
      crowd_control.first_masked(mask: spell.target_cc_mask, held:)
      |> result.map(fn(state) {
        cast_result.from_value(crowd_control.target_result(state:))
      })
      |> option.from_result
  }
}

/// An activate cast of a planned spell at a creature or object, for the cast time given:
/// refused by the target's life and states (`target_state_refusal`), then with the range's
/// result when the caster stands out of the limits the creature and the spell hold, else
/// started (`0x1403b2240` tests the life and the states before the range).
fn activation_in_range(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  target target: activate.Body,
  alive alive: Bool,
  held held: List(CrowdControlState),
  by_item by_item: Bool,
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
  effects effects: List(activate.ActivateEffect),
  dropped_signals dropped_signals: List(Spell4EffectsId),
  limits limits: activate.Limits,
) -> Result(#(State, List(Effect)), Refusal) {
  case target_state_refusal(spell:, alive:, held:) {
    Some(result) ->
      Ok(
        #(cast, [
          cast_frame.refused(
            client_cast_id:,
            spell4_id: spell.spell4_id.value,
            result:,
          ),
        ]),
      )
    None ->
      activation_reached(
        cast:,
        caster:,
        caster_radius:,
        now_ms:,
        client_cast_id:,
        unit_id:,
        creature_id:,
        creature:,
        target:,
        alive:,
        by_item:,
        spell:,
        cast_time_ms:,
        effects:,
        dropped_signals:,
        limits:,
      )
  }
}

/// An activate cast whose target's life and states, and cast group, let it through: refused
/// with the range's result when the caster stands out of the limits the creature and the
/// spell hold, else started.
fn activation_reached(
  cast cast: State,
  caster caster: Caster,
  caster_radius caster_radius: Float,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  creature creature: activate.Creature,
  target target: activate.Body,
  alive alive: Bool,
  by_item by_item: Bool,
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
  effects effects: List(activate.ActivateEffect),
  dropped_signals dropped_signals: List(Spell4EffectsId),
  limits limits: activate.Limits,
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  case
    activate.range_of(
      limits: activate.limits_for(creature:, spell4_id:, spell: limits),
      caster: activate.Body(place: caster.place, radius: caster_radius),
      target:,
    )
  {
    activate.TooClose -> refusal(cast_result.TargetRangeMin)
    activate.TooFar -> refusal(cast_result.TargetRangeMax)
    activate.TooHigh -> refusal(cast_result.TargetRangeVertical)
    activate.Within ->
      activation_started(
        cast:,
        caster:,
        now_ms:,
        client_cast_id:,
        unit_id:,
        creature_id:,
        alive_at_press: alive,
        by_item:,
        spell: activation_spell(spell:, cast_time_ms:),
        interaction: interaction_of(spell:),
        effects:,
        dropped_signals:,
      )
  }
}

/// What the client's interaction of a cast of the spell has to answer: a castMethod 5
/// spell waits for it.
fn interaction_of(spell spell: Spell) -> Interaction {
  use <- bool.guard(
    when: spell.method == spell_plan.ClientSideInteraction,
    return: AwaitingAnswer,
  )
  NoInteraction
}

/// The plan's spell as an activate cast casts it, with the cast time the client takes for
/// it: the creature's `activateSpellCastTime` when the creature lists the spell and it is
/// not 0, else the spell's own castTime (`0x1407a1680`, `0x14054e340`, GetActivateCastTime;
/// `activate.cast_time_for`). A Normal spell, and a spell of any other
/// built method, goes once after that time with the cast bar shown, whatever its phases or
/// channel are. A Channeled spell whose activate time is its channelMaxTime keeps its
/// channel: the client replaces only the cast's duration and keeps the go count of the
/// channel (`0x14053d1f0.activate_channel`, `cast.channel_sequence`), so its gos and its
/// finish are the channel's. A castMethod 5 spell casts the same way as a Normal one, its bar
/// shown only when that time is not 0 (`opcode.0x7ff.csi_cast_bar`); its go also waits for
/// the client's answer (`asked`). A spell whose method is not built is left as it is, so
/// the verdict refuses it.
///
/// Gap: a Channeled spell whose activate time is not its channelMaxTime (one whose own
/// castTime is 0 with no creature time, or a creature time other than the channel's) is
/// cast as a Normal spell: the client keeps its go count and the times the server picks
/// for them are not settled, the issue "Quests, zones and prerequisites work on the real
/// client" (#334).
fn activation_spell(
  spell spell: Spell,
  cast_time_ms cast_time_ms: Int,
) -> Spell {
  let interaction = spell.method == spell_plan.ClientSideInteraction
  use <- bool.guard(
    when: !cast_cost.is_built(spell.method) && !interaction,
    return: spell,
  )
  let cast_time_ms = case cast_time_ms {
    0 -> spell.cast_time_ms
    creature_time -> creature_time
  }
  case spell.channel {
    Some(channel)
      if spell.method == spell_plan.Channeled
      && cast_time_ms == channel.max_time_ms
    ->
      spell_plan.Spell(
        ..spell,
        cast_time_ms:,
        cast_bar: spell_plan.ShowsCastBar,
        phase_delays_ms: [],
        stages: [],
      )
    Some(_) | None ->
      spell_plan.Spell(
        ..spell,
        method: spell_plan.Normal,
        cast_time_ms:,
        cast_bar: case interaction && cast_time_ms == 0 {
          True -> spell_plan.HidesCastBar
          False -> spell_plan.ShowsCastBar
        },
        phase_delays_ms: [],
        channel: None,
        stages: [],
      )
  }
}

/// The activate cast of `unit_id` under the same checks as a press of its spell, then
/// started: the verdict's holds are refusals here, since the client does not send the
/// cast again.
fn activation_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  alive_at_press alive_at_press: Bool,
  by_item by_item: Bool,
  spell spell: Spell,
  interaction interaction: Interaction,
  effects effects: List(activate.ActivateEffect),
  dropped_signals dropped_signals: List(Spell4EffectsId),
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  accepted_and_started(
    cast:,
    caster:,
    now_ms:,
    client_cast_id:,
    spell:,
    primary_target: unit_id,
    role: Activation(
      activating: Activating(
        unit_id:,
        creature_id:,
        alive_at_press:,
        by_item:,
        effects:,
      ),
      interaction:,
    ),
    target_subject: None,
    dropping: fn(cast) {
      signals_dropped(
        cast:,
        spell4_id:,
        unit_id:,
        creature_id:,
        dropped_signals:,
      )
    },
  )
}

/// A cast the client sent a cast id for (an activate or a shortcut cast), under the same
/// checks as a press of its spell, then started in `role`: the verdict's holds are
/// refusals, since the client does not send the cast again. `dropping` is what the start
/// leaves to log, after the payments and before the start's own effects.
fn accepted_and_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Int,
  spell spell: Spell,
  primary_target primary_target: Int,
  role role: Role,
  target_subject target_subject: Option(prerequisite.Subject),
  dropping dropping: fn(State) -> #(State, List(Effect)),
) -> Result(#(State, List(Effect)), Refusal) {
  let spell4_id = spell.spell4_id.value
  let refusal = fn(result) {
    Ok(#(cast, [cast_frame.refused(client_cast_id:, spell4_id:, result:)]))
  }
  use <- bool.guard(
    when: answer_is_out(cast:),
    return: refusal(cast_result.SpellAlreadyCasting),
  )
  case
    verdict(cast:, caster:, spell:, now_ms:, is_release: False, target_subject:)
  {
    Refuse(result:) -> refusal(result)
    Hold(..) -> refusal(cast_result.SpellGlobalCooldown)
    HoldForCast -> refusal(cast_result.SpellAlreadyCasting)
    NotBuilt(result:, why:, issue:) ->
      not_built_refusal(
        cast:,
        client_cast_id:,
        spell4_id:,
        key: case role {
          Shortcut(..) -> UnbuiltShortcut(spell4_id:)
          Child | Base(..) | Stage(..) | Passive | Activation(..) ->
            UnbuiltSpell(spell4_id:)
        },
        result:,
        why:,
        issue:,
      )
    Accept(paid:) -> {
      let #(taken, reserved) = case cast_cost.pays_at_accept(spell:) {
        True -> #(cast_cost.paying(payments: paid.payments), [])
        False -> #([], paid.payments)
      }
      let #(cast, started) =
        start(
          cast:,
          caster:,
          now_ms:,
          spell:,
          root: spell.spell4_id,
          parent: None,
          primary_target:,
          client_cast_id: Some(client_cast_id),
          role:,
          spent: paid.spent,
          reserved:,
        )
      let #(cast, dropped) = dropping(cast)
      Ok(#(cast, list.flatten([taken, dropped, started])))
    }
  }
}

/// The log of the RavelSignal rows an activate cast drops, the first time for the spell:
/// the server has no script to start for them (`activate.activate_rows_of`).
fn signals_dropped(
  cast cast: State,
  spell4_id spell4_id: Int,
  unit_id unit_id: Int,
  creature_id creature_id: Int,
  dropped_signals dropped_signals: List(Spell4EffectsId),
) -> #(State, List(Effect)) {
  let key = DroppedSignals(spell4_id:)
  case dropped_signals == [] || set.contains(cast.logged, key) {
    True -> #(cast, [])
    False -> #(State(..cast, logged: set.insert(cast.logged, key)), [
      Log(
        level: LogWarning,
        text: "the activate cast of Spell4 "
          <> int.to_string(spell4_id)
          <> " at unit "
          <> int.to_string(unit_id)
          <> " (Creature2 "
          <> int.to_string(creature_id)
          <> ") drops the RavelSignal effects "
          <> string.join(
          list.map(dropped_signals, fn(effect_id) {
            int.to_string(effect_id.value)
          }),
          ", ",
        )
          <> ": the server has no script to start for them",
      ),
    ])
  }
}

/// The log of the crowd-control rows the plan drops from a spell (`Spell.dropped_controls`),
/// the first time a cast of the spell starts: each holds a state on another unit until
/// removed, which no rule of the server ends when the spell ends, so the cast lands none
/// of them.
fn controls_dropped(
  cast cast: State,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let key = DroppedControls(spell4_id: spell.spell4_id.value)
  case spell.dropped_controls == [] || set.contains(cast.logged, key) {
    True -> #(cast, [])
    False -> #(State(..cast, logged: set.insert(cast.logged, key)), [
      Log(
        level: LogWarning,
        text: "the cast of Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> " drops the crowd-control effects "
          <> string.join(
          list.map(spell.dropped_controls, fn(effect_id) {
            int.to_string(effect_id.value)
          }),
          ", ",
        )
          <> ", each a state on another unit held until removed, which the server does not end with its spell yet, the issue "
          <> issue_name(issue: UntilRemovedIssue),
      ),
    ])
  }
}

/// A right-click refused because the server does not build what the cast needs: the
/// refusal, with a log the first time for `key`.
fn not_built_refusal(
  cast cast: State,
  client_cast_id client_cast_id: Int,
  spell4_id spell4_id: Int,
  key key: Unbuilt,
  result result: cast_result.CastResult,
  why why: String,
  issue issue: Issue,
) -> Result(#(State, List(Effect)), Refusal) {
  let refusal = cast_frame.refused(client_cast_id:, spell4_id:, result:)
  let what = case key {
    UnbuiltShortcut(..) | UnreadShortcutPick(..) | UnbuiltPlayerTarget(..) ->
      "the shortcut cast of Spell4 "
    UnbuiltItemSpell(..)
    | UnbuiltItemCharges(..)
    | UnreadItemPrerequisite(..) -> "the use of an item whose spell is Spell4 "
    UnbuiltSpell(..)
    | UnreadPrerequisite(..)
    | UnreadLinkPrerequisite(..)
    | DroppedSignals(..)
    | DroppedControls(..) -> "the activate cast of Spell4 "
  }
  case set.contains(cast.logged, key) {
    True -> Ok(#(cast, [refusal]))
    False ->
      Ok(
        #(State(..cast, logged: set.insert(cast.logged, key)), [
          Log(
            level: LogWarning,
            text: what
              <> int.to_string(spell4_id)
              <> " "
              <> why
              <> ", the issue "
              <> issue_name(issue:)
              <> ": it is refused with "
              <> int.to_string(cast_result.to_value(result)),
          ),
          refusal,
        ]),
      )
  }
}

/// What an input did, with `StealthChanged` after its own effects when the caster's stealth
/// is not what it was in `cast`, the state before the input: one per input, however many
/// Stealth rows came and went. The input's events are recorded as pending, to be matched
/// against the held procs once the connection has drawn what they need
/// (`proc_draws_needed`, `procs_fire`), in this order: `own` are the input's own events,
/// then a heal and a receipt for each `Heal` change the input's effects start on the
/// caster, then the events the input raised as it ran (`UsesAbility` in `start`), then a
/// `SpendsResource` for each payment among its effects, then the stealth change. `step` is
/// the input's own work.
fn settled(
  cast cast: State,
  own own: List(proc.Event),
  step step: fn() -> #(State, List(Effect)),
) -> #(State, List(Effect)) {
  let #(after, effects) = step()
  let #(stealth, moved) = case
    cast_state.stealthed(cast: after) == cast_state.stealthed(cast:)
  {
    True -> #([], [])
    False -> {
      let stealthed = cast_state.stealthed(cast: after)
      let change = case stealthed {
        True -> spell_plan.EnteredStealth
        False -> spell_plan.LeftStealth
      }
      #([proc.Event(trigger: change, other_unit: None, spell: None)], [
        StealthChanged(stealthed:),
      ])
    }
  }
  let before_count = list.length(cast.pending)
  let events =
    list.flatten([
      own,
      heals_landed(before: cast, after:, effects:),
      list.drop(after.pending, before_count),
      resources_spent(effects:),
      stealth,
    ])
  #(
    State(
      ..after,
      pending: list.append(list.take(after.pending, before_count), events),
    ),
    list.append(effects, moved),
  )
}

/// A `SpendsResource` event for each payment the effects take from the caster's class
/// resource. A guess: the event names no spell, so a group filter never matches it (a
/// payment does not say which spell it is for, and no client code reads a Proc row,
/// `Spell4Effects.effectType.14.dataBits00`).
fn resources_spent(effects effects: List(Effect)) -> List(proc.Event) {
  list.filter_map(effects, fn(effect) {
    case effect {
      Pay(..) ->
        Ok(proc.Event(
          trigger: spell_plan.SpendsResource,
          other_unit: None,
          spell: None,
        ))
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | Gain(..)
      | CasterChangeStarts(..)
      | CasterChangeEnds(..)
      | TargetChangeStarts(..)
      | TargetChangeEnds(..)
      | ForcedMoveStarts(..)
      | Activated(..)
      | ShortcutCast(..)
      | StealthChanged(..) -> Error(Nil)
    }
  })
}

/// The events of the heals an input's effects start on the caster: for each `Heal` change
/// in order, a `LandsHeal` and then a `ReceivesHeal`, since the caster is the one who
/// heals and the one healed (a heal aimed at another unit starts no change on the caster
/// and raises neither). Two readings are guesses: a heal that moves nothing is one as well,
/// and a heal of the shields or of any other vital counts as a heal as a health heal
/// does (the client reads no Proc row to say what a heal is,
/// `Spell4Effects.effectType.14.dataBits00`). The event's spell is the spell of the cast
/// whose row healed, as `after` holds it or, for a cast the input ended, `before`.
/// `LandsCriticalHeal` is never raised: no heal is rolled a critical yet, and issue 830
/// closes that gap.
fn heals_landed(
  before before: State,
  after after: State,
  effects effects: List(Effect),
) -> List(proc.Event) {
  list.flat_map(effects, fn(effect) {
    case effect {
      CasterChangeStarts(source:, change: Heal(..)) -> {
        let spell =
          option.map(
            option.from_result(
              result.lazy_or(
                cast_state.holder_of(cast: after, cast_id: source.cast_id),
                fn() {
                  cast_state.holder_of(cast: before, cast_id: source.cast_id)
                },
              ),
            ),
            fn(holder) { event_spell(spell: holder.spell) },
          )
        [
          proc.Event(trigger: spell_plan.LandsHeal, other_unit: None, spell:),
          proc.Event(trigger: spell_plan.ReceivesHeal, other_unit: None, spell:),
        ]
      }
      CasterChangeStarts(change: Property(..), ..)
      | CasterChangeStarts(change: Absorb(..), ..)
      | CasterChangeStarts(change: Look(..), ..) -> []
      Send(..)
      | Tell(..)
      | StartTimer(..)
      | CancelTimer(..)
      | Log(..)
      | Strike(..)
      | TickStrike(..)
      | Pay(..)
      | Gain(..)
      | CasterChangeEnds(..)
      | TargetChangeStarts(..)
      | TargetChangeEnds(..)
      | ForcedMoveStarts(..)
      | Activated(..)
      | ShortcutCast(..)
      | StealthChanged(..) -> []
    }
  })
}

/// The spell of an event as a proc's filter reads it.
fn event_spell(spell spell: Spell) -> proc.EventSpell {
  proc.EventSpell(
    spell4_id: spell.spell4_id,
    groups: spell.groups,
    school: spell.school,
  )
}

/// The events a strike round's units give the holder, in the round's order: for each
/// description of the damage that landed on a creature, a hit, a melee hit when the spell is
/// of school 1, a critical when the description's combat result is a critical (and a finisher
/// critical, which the row's group filter narrows to finishers) and a kill
/// when it killed the creature, so a go with two damage rows on one creature raises two
/// hits and a spell that only selects a unit (no description) raises none; then a taunt
/// landed for each Taunt state the creature took, a guarded creature's included. A
/// deflected unit raises a deflect and no hit, and an immune one no hit, and a player
/// a creature's attack hit is not the holder's strike (a guess for each description
/// counting, for a deflect, an immunity, a finisher critical and a taunt: no client code
/// reads a Proc row, `Spell4Effects.effectType.14.client_evaluation`).
fn hit_events(
  spell spell: Spell,
  struck struck: List(Struck),
) -> List(proc.Event) {
  let on = fn(unit_id, trigger) {
    proc.Event(
      trigger:,
      other_unit: Some(unit_id),
      spell: Some(event_spell(spell:)),
    )
  }
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, unit: HitCreature(..), descriptions:, controls:, ..) ->
        list.append(
          list.flat_map(descriptions, fn(description) {
            list.map(hit_triggers(spell:, description:), on(unit_id, _))
          }),
          taunts_landed(unit_id:, controls:, on:),
        )
      Immune(unit_id:, unit: HitCreature(..), controls:, ..) ->
        taunts_landed(unit_id:, controls:, on:)
      Deflected(unit_id:) -> [on(unit_id, spell_plan.FoeDeflects)]
      Hit(unit: HitPlayer, ..) | Immune(unit: HitPlayer, ..) -> []
    }
  })
}

/// A taunt landed event for each Taunt state a unit took.
fn taunts_landed(
  unit_id unit_id: Int,
  controls controls: List(strike_tell.ControlLanded),
  on on: fn(Int, spell_plan.Trigger) -> proc.Event,
) -> List(proc.Event) {
  list.filter_map(controls, fn(control) {
    case control.tell.row.state == crowd_control_state.Taunt {
      True -> Ok(on(unit_id, spell_plan.LandsTaunt))
      False -> Error(Nil)
    }
  })
}

/// The triggers one damage description of a strike on a creature raises.
fn hit_triggers(
  spell spell: Spell,
  description description: hit.Description,
) -> List(spell_plan.Trigger) {
  let critical = description.damage.combat_result == combat_result.Critical
  list.flatten([
    [spell_plan.LandsHit],
    case spell.school {
      1 -> [spell_plan.LandsMeleeHit]
      _ -> []
    },
    case critical {
      True -> [spell_plan.LandsCritical, spell_plan.LandsFinisherCritical]
      False -> []
    },
    case description.damage.killed != 0 {
      True -> [spell_plan.Kills]
      False -> []
    },
  ])
}

/// Whether an input raised events the held procs have not been matched against yet.
pub fn has_pending(cast cast: State) -> Bool {
  cast.pending != []
}

/// The state with the events the facts raise appended to the pending ones, in the facts'
/// order. A resource that changed at all raises `ResourceCrosses`, and a fall of the
/// Stalker's suit power also `SuitPowerDrops`; the proc's own holder gate then decides
/// whether the value is the one it waits for, on the holder as it is after the change
/// (`procs_fire`). Two readings are guesses: the change of any slot is an event of kind 87,
/// and the gate is not asked whether the value was on the other side before, so a change
/// that stays inside or goes on past the gated range raises the event too (no client code
/// reads a Proc row, `Spell4Effects.effectType.14.dataBits00`).
pub fn raised(cast cast: State, facts facts: List(Fact)) -> State {
  let events =
    list.flat_map(facts, fn(fact) {
      case fact {
        StartedMoving -> [
          proc.Event(
            trigger: spell_plan.StartsMoving,
            other_unit: None,
            spell: None,
          ),
        ]
        ResourceMoved(slot:, from:, to:) if from != to ->
          list.flatten([
            [
              proc.Event(
                trigger: spell_plan.ResourceCrosses,
                other_unit: None,
                spell: None,
              ),
            ],
            case slot == cast_state.suit_power_slot && to <. from {
              True -> [
                proc.Event(
                  trigger: spell_plan.SuitPowerDrops,
                  other_unit: None,
                  spell: None,
                ),
              ]
              False -> []
            },
          ])
        ResourceMoved(..) -> []
      }
    })
  State(..cast, pending: list.append(cast.pending, events))
}

/// The words and the gate rolls the connection draws before the pending events are matched
/// (`procs_fire`): for each pending event, each held proc of its trigger takes what
/// `proc.draws_needed` gives, whether or not an earlier check stops it, so the count is
/// exact. A state with nothing pending needs none.
pub fn proc_draws_needed(cast cast: State) -> #(Int, Int) {
  list.fold(cast.pending, #(0, 0), fn(total, event) {
    list.fold(dict.values(cast.procs), total, fn(total, held) {
      case held.row.trigger == event.trigger {
        True -> {
          let #(words, rolls) = proc.draws_needed(row: held.row)
          #(total.0 + words, total.1 + rolls)
        }
        False -> total
      }
    })
  })
}

/// The units the pending events concern besides the caster, which the event gates read:
/// the connection takes their poses, checklist indexes and kinds from its picture of the
/// caster's world for `procs_fire`.
pub fn pending_units(cast cast: State) -> List(Int) {
  list.filter_map(cast.pending, fn(event) {
    option.to_result(event.other_unit, Nil)
  })
  |> list.unique
}

/// The held procs fire for the pending events, in the order they happened; within an event,
/// in source order, the cast id and then the effect id, which is row order for one holder. The
/// events are cleared. A proc whose node the input took off is not held, and one the input
/// applied is. `draws` are the 32-bit words and `rolls` the gate rolls drawn for
/// `proc_draws_needed`, taken in the order the procs are matched; `poses`, `indexes` and
/// `units` are those of `pending_units` as `went` takes them, which an event gate against the
/// event's unit reads. A fire's own go is an input of its own, so it raises its own events then
/// and no event raised here is matched in this pass.
pub fn procs_fire(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  draws draws: List(Int),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  let events = cast.pending
  let cast = State(..cast, pending: [])
  let ordered =
    dict.to_list(cast.procs)
    |> list.sort(fn(first, second) {
      int.compare({ first.0 }.cast_id, { second.0 }.cast_id)
      |> order.break_tie(int.compare(
        { first.0 }.effect_id.value,
        { second.0 }.effect_id.value,
      ))
    })
  let #(cast, effects, _, _) =
    list.fold(events, #(cast, [], draws, rolls), fn(so_far, event) {
      let #(cast, effects, draws, rolls) = so_far
      list.filter(ordered, fn(entry) {
        { entry.1 }.row.trigger == event.trigger
      })
      |> list.fold(#(cast, effects, draws, rolls), fn(so_far, entry) {
        let #(cast, effects, draws, rolls) = so_far
        let source = entry.0
        let row = { entry.1 }.row
        let #(words, roll_count) = proc.draws_needed(row:)
        let #(taken, draws) = list.split(draws, words)
        let #(own_rolls, rolls) = list.split(rolls, roll_count)
        let #(cast, more) = case dict.get(cast.procs, source) {
          Error(Nil) -> #(cast, [])
          Ok(held) ->
            proc_matched(
              cast:,
              caster:,
              now_ms: now.monotonic_ms,
              event:,
              source:,
              held:,
              draw: option.from_result(list.first(taken)),
              rolls: own_rolls,
              poses:,
              indexes:,
              units:,
            )
        }
        #(cast, list.append(effects, more), draws, rolls)
      })
    })
  #(cast, effects)
}

/// One held proc against one event of its trigger: what `proc.decide` gives, carried out. The
/// holder's subject is the caster as `subject_of` has it, and the event's the struck unit as
/// a Proxy's target gate reads it (`struck_subject`), or the caster again for an event with
/// no other unit.
fn proc_matched(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  event event: proc.Event,
  source source: unit_properties.Source,
  held held: HeldProc,
  draw draw: Option(Int),
  rolls rolls: List(Int),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> #(State, List(Effect)) {
  let row = held.row
  case cast_state.holder_of(cast:, cast_id: source.cast_id) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " is held by the cast "
          <> int.to_string(source.cast_id)
          <> ", which is neither live nor lingering, so it does not fire",
      ),
    ])
    Ok(holder) -> {
      let holder_subject = subject_of(cast:, caster:)
      let event_subject = case event.other_unit {
        Some(unit) ->
          struck_subject(
            cast:,
            caster:,
            primary_target: unit,
            poses:,
            indexes:,
            units:,
          )
        None -> holder_subject
      }
      case
        proc.decide(
          row:,
          fires_ms: held.fires_ms,
          now_ms:,
          event:,
          holder_unit: caster.unit_id,
          holder_subject:,
          event_subject:,
          draw:,
          rolls:,
        )
      {
        proc.Fires(at:, delay_ms:) ->
          proc_fires(
            cast:,
            caster:,
            now_ms:,
            source:,
            held:,
            holder:,
            at:,
            delay_ms:,
          )
        proc.CannotTell(why:) -> #(cast, [Log(level: LogDebug, text: why)])
        proc.OutOfLimit
        | proc.FilteredOut
        | proc.HolderGateFails
        | proc.EventGateFails
        | proc.MissedChance -> #(cast, [])
      }
    }
  }
}

/// A proc that fires: refused for a caster of a life its spell's caster condition does not
/// allow (`Spell4.spell4ConditionsIdCaster`, `cast.dead_player`), which writes a debug line
/// and records no fire; else recorded as a fire at the event, and its spell cast at `at` at
/// once or, with a delay, when `ProcDue` runs out. The cast starts as a child of the holder's
/// spell does: the holder's spell is its root and parent, no 0x7fd.
fn proc_fires(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  held held: HeldProc,
  holder holder: Holder,
  at at: Int,
  delay_ms delay_ms: Int,
) -> #(State, List(Effect)) {
  let row = held.row
  case proc_refusal(caster:, row:, holder:) {
    Some(refusal) -> #(cast, [refusal])
    None -> {
      let cast =
        State(
          ..cast,
          procs: dict.insert(
            cast.procs,
            source,
            HeldProc(row:, fires_ms: [
              now_ms,
              ..proc.counted(limit: row.limit, fires_ms: held.fires_ms, now_ms:)
            ]),
          ),
        )
      case delay_ms {
        0 -> proc_started(cast:, caster:, now_ms:, row:, holder:, at:)
        _ -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: ProcDue(source:, row:, at:),
              after_ms: delay_ms,
            )
          #(cast, [start])
        }
      }
    }
  }
}

/// The debug line that says a proc's spell is not cast because its caster condition refuses a
/// caster of the life the caster has, or none.
fn proc_refusal(
  caster caster: Caster,
  row row: spell_plan.ProcRow,
  holder holder: Holder,
) -> Option(Effect) {
  case spell_plan.refused_life(spell: row.spell, dead: caster.dead) {
    None -> None
    Some(_) ->
      Some(Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of Spell4 "
          <> int.to_string(holder.spell.spell4_id.value)
          <> " does not cast Spell4 "
          <> int.to_string(row.spell.spell4_id.value)
          <> ", whose caster condition refuses a caster that is "
          <> case caster.dead {
          True -> "dead"
          False -> "alive"
        },
      ))
  }
}

/// The cast of a proc's spell at the unit `at`, started as a child of the holder's spell.
fn proc_started(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  row row: spell_plan.ProcRow,
  holder holder: Holder,
  at at: Int,
) -> #(State, List(Effect)) {
  start(
    cast:,
    caster:,
    now_ms:,
    spell: row.spell,
    root: holder.spell.spell4_id,
    parent: Some(holder.spell.spell4_id),
    primary_target: at,
    client_cast_id: None,
    role: Child,
    spent: None,
    reserved: [],
  )
}

/// A fire's delay ran out: its spell is cast, unless its holder's cast has ended since or the
/// caster's life is one the spell refuses now.
fn proc_due(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  source source: unit_properties.Source,
  row row: spell_plan.ProcRow,
  at at: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id: source.cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(holder) ->
      case proc_refusal(caster:, row:, holder:) {
        Some(refusal) -> #(cast, [refusal])
        None -> proc_started(cast:, caster:, now_ms:, row:, holder:, at:)
      }
  }
}

/// The Proc rows of a go that applied, each held by the cast `cast_id` from this go on;
/// a row the cast already holds keeps its fires, as a later go of the same cast is the
/// same node.
fn procs_held(
  cast cast: State,
  cast_id cast_id: Int,
  applied applied: Applied,
) -> #(State, List(Effect)) {
  let #(never, held) =
    list.partition(applied.procs, fn(row) {
      row.trigger == spell_plan.Died && cast.passive != Some(cast_id)
    })
  let procs =
    list.fold(held, cast.procs, fn(procs, row) {
      let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
      dict.upsert(procs, source, fn(found) {
        case found {
          Some(already) -> already
          None -> HeldProc(row:, fires_ms: [])
        }
      })
    })
  #(
    State(..cast, procs:),
    list.map(never, fn(row) {
      Log(
        level: LogDebug,
        text: "the Proc effect "
          <> int.to_string(row.effect_id.value)
          <> " of kind 0 is held by a cast that is not the innate passive, which a death ends before the proc is matched, so it is not held",
      )
    }),
  )
}

/// A step's result with the held press started when the step cleared the current
/// cast it waited for.
fn released(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = cast_cost.after_payments(caster:, effects:)
  case cast.held {
    Some(Held(client_cast_id:, resolution:, until: CastClears)) ->
      case cast.current {
        None -> {
          let #(cast, started) =
            press_of(
              cast: State(..cast, held: None),
              caster:,
              now_ms:,
              client_cast_id:,
              resolution:,
            )
          #(cast, list.append(effects, started))
        }
        Some(_) -> taken
      }
    Some(Held(until: CooldownEnds, ..)) | None -> taken
  }
}

fn pressed(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use press <- result.try(
    cast_ability.decode(body)
    |> client_connection.decoded(message_id: cast_ability.message_id)
    |> result.map_error(NotDecoded),
  )
  use <- bool.guard(
    when: press.client_cast_id == 0,
    return: Error(NoClientCastId),
  )
  use <- bool.guard(
    when: press.press == 0,
    return: Ok(
      #(cast, [
        Log(
          level: LogInfo,
          text: "a press with the press bit 0 is a console setting's, which is not built",
        ),
      ]),
    ),
  )
  case ability_at(caster:, plans:, bag_index: press.bag_index) {
    Error(Nil) ->
      Ok(
        #(cast, [
          cast_frame.refused_unknown(
            client_cast_id: press.client_cast_id,
            spell4_id: 0,
          ),
        ]),
      )
    Ok(plain) -> {
      let ability = surged(cast:, caster:, ability: plain)
      case resolved(cast:, caster:, bag_spell: plain.spell4_id, ability:) {
        Error(Nil) ->
          Ok(
            #(cast, [
              cast_frame.refused_unknown(
                client_cast_id: press.client_cast_id,
                spell4_id: ability.spell4_id.value,
              ),
            ]),
          )
        Ok(resolution) ->
          Ok(press_of(
            cast:,
            caster:,
            now_ms: now.monotonic_ms,
            client_cast_id: Some(press.client_cast_id),
            resolution:,
          ))
      }
    }
  }
}

/// The spell a press of the ability casts: under Spell Surge, the alternate the ability
/// names when the player's book holds it, else the ability itself. The client makes the
/// swap inside the press, before the threshold step, so an open threshold is looked for
/// under the swapped ability (`CastAbilityBagSpell` `0x14039a040`, `SpellslingerSurgedSpell`
/// `0x1405e7e50`, `IsSpellSurgeActive` `0x1405e7d10`, `GetAbilityBookSpell` `0x1403bad30`).
fn surged(
  cast cast: State,
  caster caster: Caster,
  ability ability: Spell,
) -> Spell {
  case ability.alternate {
    Some(alternate) ->
      case
        list.contains(caster.book, alternate.spell4_base_id)
        && list.any(holds_on(cast:, unit_id: caster.unit_id), fn(hold) {
          hold.spell4_id == caster.surge_spell
        })
      {
        True -> alternate
        False -> ability
      }
    None -> ability
  }
}

/// Whether the held key is the ability's own or the alternate it is swapped for.
fn is_held(held held: Spell, ability ability: Spell) -> Bool {
  held.spell4_id == ability.spell4_id
  || option.map(held.alternate, fn(alternate) { alternate.spell4_id })
  == Some(ability.spell4_id)
}

/// The ability the player holds at the bag index, as the plans have it.
fn ability_at(
  caster caster: Caster,
  plans plans: Plans,
  bag_index bag_index: Int,
) -> Result(Spell, Nil) {
  list.drop(caster.abilities, bag_index)
  |> list.first
  |> result.try(fn(base) { spell_plan.in_plans(plans:, base:) })
}

/// The key of an ability goes down (held 1) or up (held 0). The client's reader
/// refuses a body longer or shorter than the message (`opcode.0x4db`), which ends
/// the connection, and a bag index with no ability is answered as a 0x9a's is,
/// with the client cast id 0 the client shows with no pending cast
/// (`cast.hold_stop`).
fn key_held(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  plans plans: Plans,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use change <- result.try(
    ability_hold.decode(body)
    |> client_connection.decoded(message_id: ability_hold.message_id)
    |> result.map_error(NotDecoded),
  )
  let now_ms = now.monotonic_ms
  Ok(
    case
      ability_at(caster:, plans:, bag_index: change.bag_index),
      change.held == 1
    {
      Error(Nil), True -> #(cast, [
        cast_frame.refused_unknown(client_cast_id: 0, spell4_id: 0),
      ])
      Error(Nil), False -> #(cast, [
        Log(
          level: LogDebug,
          text: "the key of the bag index "
            <> int.to_string(change.bag_index)
            <> ", which holds no ability, comes up",
        ),
      ])
      Ok(ability), True -> key_down(cast:, ability:)
      Ok(ability), False -> key_up(cast:, caster:, ability:, now_ms:)
    },
  )
}

/// The ability becomes the one held: a second key down of the ability already held
/// is the same hold, and the newest ability's key replaces the held one, whose
/// cast under way ends by itself (the server's choice: the client sends each key
/// its own key up, and gives no way to hold two). Its first cast is made by
/// `continued`, once the caster is free.
fn key_down(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == ability.spell4_id -> #(
      cast,
      [],
    )
    Some(_) | None -> {
      let #(cast, cancels) = stop_holding(cast:)
      #(
        State(
          ..cast,
          holding: Some(Holding(ability:, repeat_timer: None, last_cast: None)),
        ),
        cancels,
      )
    }
  }
}

/// The ability's key comes up: its repeats stop, and the cast under way is left to
/// end. A ChargeRelease ability with its threshold open fires its charged stage, as
/// a 0x9a release does: the bag ability is swapped as a press swaps it, and the open
/// threshold is found by the swapped spell as a press finds it.
fn key_up(
  cast cast: State,
  caster caster: Caster,
  ability plain: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = case cast.holding {
    Some(Holding(ability: held, ..)) if held.spell4_id == plain.spell4_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
  let ability = surged(cast:, caster:, ability: plain)
  case threshold_of(cast:, ability:) {
    Ok(Threshold(ability: charging, ..))
      if charging.method == spell_plan.ChargeRelease
    ->
      case resolved(cast:, caster:, bag_spell: plain.spell4_id, ability:) {
        Error(Nil) -> #(cast, [
          cast_frame.refused_unknown(
            client_cast_id: 0,
            spell4_id: charging.spell4_id.value,
          ),
          ..cancels
        ])
        Ok(resolution) -> {
          let #(cast, released) =
            press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
          #(cast, list.append(cancels, released))
        }
      }
    Ok(_) | Error(Nil) -> #(cast, cancels)
  }
}

/// No ability is held: the timer that waits to repeat is cancelled.
fn stop_holding(cast cast: State) -> #(State, List(Effect)) {
  case cast.holding {
    None -> #(cast, [])
    Some(Holding(repeat_timer:, ..)) -> {
      let #(cast, cancels) = case repeat_timer {
        Some(timer) -> #(
          State(..cast, timers: dict.delete(cast.timers, timer)),
          [CancelTimer(timer:)],
        )
        None -> #(cast, [])
      }
      #(State(..cast, holding: None), cancels)
    }
  }
}

/// The timer of the held ability's repeat fired: it waits no longer, unless the
/// hold ended or moved on to another timer.
fn repeat_fired(cast cast: State, timer timer: TimerId) -> State {
  State(
    ..cast,
    holding: option.map(cast.holding, fn(holding) {
      case holding.repeat_timer == Some(timer) {
        True -> Holding(..holding, repeat_timer: None)
        False -> holding
      }
    }),
  )
}

/// A step's result with the held ability cast again when the step left nothing in
/// its way: its last cast is over, the caster's current cast is, and no timer waits
/// for a cooldown (`cast.hold_repeat`).
fn continued(
  taken taken: #(State, List(Effect)),
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, effects) = taken
  let caster = cast_cost.after_payments(caster:, effects:)
  case cast.holding {
    Some(Holding(ability:, repeat_timer: None, last_cast:)) -> {
      let #(cast, more) =
        repeated(cast:, caster:, now_ms:, ability:, last_cast:)
      #(cast, list.append(effects, more))
    }
    Some(Holding(repeat_timer: Some(_), ..)) | None -> taken
  }
}

/// The held ability's next cast: a refusal when no stage is left, nothing while its
/// last cast or the caster's current cast is under way, a timer while a cooldown
/// runs, else the press itself.
fn repeated(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  ability plain: Spell,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let ability = surged(cast:, caster:, ability: plain)
  case resolved(cast:, caster:, bag_spell: plain.spell4_id, ability:) {
    Error(Nil) -> no_stage_left(cast:, ability:)
    Ok(resolution) ->
      next_cast(cast:, caster:, now_ms:, resolution:, last_cast:)
  }
}

/// A held RapidTap ability whose threshold has no stage at its index: refused, as
/// a 0x9a press is, and the hold ends.
fn no_stage_left(
  cast cast: State,
  ability ability: Spell,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_holding(cast:)
  #(
    cast,
    list.append(cancels, [
      cast_frame.refused_unknown(
        client_cast_id: 0,
        spell4_id: ability.spell4_id.value,
      ),
    ]),
  )
}

fn next_cast(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  resolution resolution: Resolution,
  last_cast last_cast: Option(Int),
) -> #(State, List(Effect)) {
  let last_cast_is_live =
    option.map(last_cast, dict.has_key(cast.casts, _)) == Some(True)
  let blocked =
    last_cast_is_live
    || cast_cost.casting(cast)
    && !resolution.spell.ignores_casting
    || option.is_some(cast.held)
  let wait_ms = case last_cast {
    Some(_) -> cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:)
    None -> 0
  }
  case blocked, wait_ms > 0 {
    True, _ -> #(cast, [])
    False, True -> repeat_after(cast:, wait_ms:)
    False, False ->
      press_of(cast:, caster:, now_ms:, client_cast_id: None, resolution:)
  }
}

/// How long a held ability waits before it casts again: until the global cooldown
/// its last cast started and the spell's own cooldown have both ended, whether or
/// not the global cooldown would refuse the spell (the server's choice,
/// `cast.hold_repeat`). Every level-1 ability and stage starts a global cooldown or
/// has a cooldown of its own, so a repeat is never at once; a later ability with
/// neither would recast as soon as its cast ended.
fn cooldown_wait_ms(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> Int {
  let #(_, own_left) = cast_cost.cooldown_left_ms(cast:, spell:, now_ms:)
  let global_left =
    option.map(cast.global_cooldown_ends_ms, fn(ends_ms) {
      int.max(0, ends_ms - now_ms)
    })
    |> option.unwrap(0)
  int.max(global_left, own_left)
}

/// The held ability waits `wait_ms` for its cooldowns on a timer of its own.
fn repeat_after(
  cast cast: State,
  wait_ms wait_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, timer, start) =
    cast_state.armed(cast:, due: RepeatHeld, after_ms: wait_ms)
  #(
    State(
      ..cast,
      holding: option.map(cast.holding, fn(holding) {
        Holding(..holding, repeat_timer: Some(timer))
      }),
    ),
    [start],
  )
}

/// The open threshold a press finds, as the client finds it: the one whose second spell
/// is the swapped ability, else the one keyed by the swapped ability
/// (`ResolveThresholdSpell` `0x1403bfd60`, `FindThresholdBySecondSpell` `0x1403c0190`).
/// A charge opened under Spell Surge is found when Surge has ended by its second spell,
/// the bag ability the 0x816 named.
fn threshold_of(
  cast cast: State,
  ability ability: Spell,
) -> Result(Threshold, Nil) {
  case
    list.find(dict.values(cast.thresholds), fn(threshold) {
      threshold.bag_spell == ability.spell4_id
    })
  {
    Ok(threshold) -> Ok(threshold)
    Error(Nil) -> dict.get(cast.thresholds, ability.spell4_id.value)
  }
}

/// What a press of the ability casts: through its open threshold the stage at the
/// threshold's index, the ability's own spell at -1, and none past the last stage
/// (`0x1403bfd60`); with no threshold open, the ability's own spell, or for an ability
/// with no threshold time the spell of the first Proxy its caster passes
/// (`ResolveProxyByCasterApply` `0x1403d3520`, fact `cast.proxy_press`).
fn resolved(
  cast cast: State,
  caster caster: Caster,
  bag_spell bag_spell: Spell4Id,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case threshold_of(cast:, ability:), ability.press_proxies {
    Error(Nil), [_, ..] -> {
      let #(proxy, logs) =
        first_passing(
          proxies: ability.press_proxies,
          subject: subject_of(cast:, caster:),
          logs: [],
        )
      Ok(case proxy {
        Some(spell) ->
          Resolution(
            spell:,
            ability:,
            bag_spell:,
            stage: None,
            proxied: True,
            logs:,
          )
        None ->
          Resolution(
            spell: ability,
            ability:,
            bag_spell:,
            stage: None,
            proxied: False,
            logs:,
          )
      })
    }
    Error(Nil), [] | Ok(_), _ ->
      resolved_by_threshold(cast:, bag_spell:, ability:)
  }
}

/// The spell of the first Proxy of a press, in row order, whose caster apply prerequisite
/// the subject passes, and a debug line for each gate the server cannot decide, which
/// does not pass. A press draws no roll: a gate that needs one is refused at load.
fn first_passing(
  proxies proxies: List(spell_plan.PressProxy),
  subject subject: prerequisite.Subject,
  logs logs: List(Effect),
) -> #(Option(Spell), List(Effect)) {
  case proxies {
    [] -> #(None, list.reverse(logs))
    [proxy, ..rest] ->
      case
        cast_gate.gates_gate(
          gates: [proxy.gate],
          subject:,
          rolls: [],
          what: "the Proxy effect " <> int.to_string(proxy.effect_id.value),
          outcome: "so a press does not cast it",
        )
      {
        #(Starts, _) -> #(Some(proxy.spell), list.reverse(logs))
        #(GateFails, _) -> first_passing(proxies: rest, subject:, logs:)
        #(CannotTell(why:), _) ->
          first_passing(proxies: rest, subject:, logs: [
            Log(level: LogDebug, text: why),
            ..logs
          ])
      }
  }
}

/// What a press of the ability casts when only its threshold decides: the stage of its
/// open threshold, else its own spell.
fn resolved_by_threshold(
  cast cast: State,
  bag_spell bag_spell: Spell4Id,
  ability ability: Spell,
) -> Result(Resolution, Nil) {
  case threshold_of(cast:, ability:) {
    Error(Nil) ->
      Ok(
        Resolution(
          spell: ability,
          ability:,
          bag_spell:,
          stage: None,
          proxied: False,
          logs: [],
        ),
      )
    Ok(threshold) ->
      spell_plan.stage_at(spell: threshold.ability, index: threshold.index)
      |> result.map(fn(spell) {
        Resolution(
          spell:,
          ability: threshold.ability,
          bag_spell:,
          stage: case threshold.index < 0 {
            True -> None
            False -> Some(threshold.index)
          },
          proxied: False,
          logs: [],
        )
      })
  }
}

/// What a press of a spell comes to: the client's refusal, a held press or a
/// cast that starts. A press with no client cast id is a held key's (0x4DB): the
/// server mints the cast id, no 0x7fd is written, a refusal carries the client
/// cast id 0, and a cooldown or a current cast is waited for by the hold itself.
fn press_of(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let #(cast, effects) =
    press_resolved(
      cast:,
      caster:,
      now_ms:,
      client_cast_id:,
      resolution: Resolution(..resolution, logs: []),
    )
  #(cast, list.append(resolution.logs, effects))
}

/// A resolved press: the 285 refusal of a spell with no threshold time that no Proxy
/// replaced (the client tests the resolved spell, `0x1403c0144`, fact `cast.proxy_press`),
/// else the verdict on the spell. A Proxy of such a press is cast as the press itself
/// (`Base` of the Proxy's spell), so a Proxy with a threshold of its own opens it.
fn press_resolved(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  client_cast_id client_cast_id: Option(Int),
  resolution resolution: Resolution,
) -> #(State, List(Effect)) {
  let spell = resolution.spell
  let is_release = is_release(resolution:)
  let held = option.is_some(cast.held)
  let refusal = fn(result) {
    cast_frame.refused(
      client_cast_id: option.unwrap(client_cast_id, 0),
      spell4_id: spell.spell4_id.value,
      result:,
    )
  }
  let judged = case
    resolution.stage == None
    && spell_plan.lacks_threshold_time(
      method: spell.method,
      threshold_ms: spell.threshold_ms,
    )
  {
    True -> Refuse(result: cast_result.IllegalSpellCast)
    False ->
      verdict(
        cast:,
        caster:,
        spell:,
        now_ms:,
        is_release:,
        target_subject: None,
      )
  }
  case judged {
    Accept(paid:) -> {
      let payments = paid.payments
      let cast = case client_cast_id {
        Some(_) -> cast
        None ->
          hold_started(
            cast:,
            ability: resolution.ability,
            cast_id: cast_state.next_cast_id(cast:, caster:),
          )
      }
      let #(taken, reserved) = case cast_cost.pays_at_accept(spell:) {
        True -> #(cast_cost.paying(payments:), [])
        False -> #([], payments)
      }
      let #(cast, started) = case resolution.stage {
        None ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: None,
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Base(
              ability: case resolution.proxied {
                True -> spell
                False -> resolution.ability
              },
              bag_spell: resolution.bag_spell,
            ),
            spent: paid.spent,
            reserved:,
          )
        Some(index) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell:,
            root: resolution.ability.spell4_id,
            parent: Some(resolution.ability.spell4_id),
            primary_target: caster.unit_id,
            client_cast_id:,
            role: Stage(ability: resolution.ability, index:),
            spent: paid.spent,
            reserved:,
          )
      }
      #(cast, list.append(taken, started))
    }
    Refuse(result:) ->
      refused_hold(
        cast:,
        client_cast_id:,
        ability: resolution.ability,
        effects: [
          refusal(result),
        ],
      )
    NotBuilt(result:, why:, issue:) ->
      case set.contains(cast.logged, UnbuiltSpell(spell.spell4_id.value)) {
        True ->
          refused_hold(
            cast:,
            client_cast_id:,
            ability: resolution.ability,
            effects: [refusal(result)],
          )
        False ->
          refused_hold(
            cast: State(
              ..cast,
              logged: set.insert(
                cast.logged,
                UnbuiltSpell(spell.spell4_id.value),
              ),
            ),
            client_cast_id:,
            ability: resolution.ability,
            effects: [
              Log(
                level: LogWarning,
                text: "the ability with Spell4 "
                  <> int.to_string(spell.spell4_id.value)
                  <> " "
                  <> why
                  <> ", the issue "
                  <> issue_name(issue:)
                  <> ": it is refused with "
                  <> int.to_string(cast_result.to_value(result)),
              ),
              refusal(result),
            ],
          )
      }
    Hold(..) | HoldForCast if is_release && held -> #(cast, [
      refusal(cast_result.SpellAlreadyCasting),
    ])
    Hold(wait_ms:) ->
      case client_cast_id, is_release {
        None, False -> repeat_after(cast:, wait_ms:)
        Some(_), _ | None, True -> {
          let #(cast, _, start) =
            cast_state.armed(cast:, due: StartHeld, after_ms: wait_ms)
          #(
            State(
              ..cast,
              held: Some(Held(client_cast_id:, resolution:, until: CooldownEnds)),
            ),
            [start],
          )
        }
      }
    HoldForCast ->
      case client_cast_id, is_release {
        None, False -> #(cast, [])
        Some(_), _ | None, True -> #(
          State(
            ..cast,
            held: Some(Held(client_cast_id:, resolution:, until: CastClears)),
          ),
          [],
        )
      }
  }
}

/// The ability's hold has started the cast `cast_id`, so its cooldowns are waited
/// for from now on and no longer refused.
fn hold_started(
  cast cast: State,
  ability ability: Spell,
  cast_id cast_id: Int,
) -> State {
  case cast.holding {
    Some(Holding(ability: held, ..) as holding) ->
      case is_held(held:, ability:) {
        True ->
          State(
            ..cast,
            holding: Some(Holding(..holding, last_cast: Some(cast_id))),
          )
        False -> cast
      }
    None -> cast
  }
}

/// A refusal of a press written; a refused held key stops its hold, which the
/// client does not know (it shows the failure and goes on holding).
fn refused_hold(
  cast cast: State,
  client_cast_id client_cast_id: Option(Int),
  ability ability: Spell,
  effects effects: List(Effect),
) -> #(State, List(Effect)) {
  case client_cast_id, cast.holding {
    None, Some(Holding(ability: held, ..)) ->
      case is_held(held:, ability:) {
        True -> {
          let #(cast, cancels) = stop_holding(cast:)
          #(cast, list.append(cancels, effects))
        }
        False -> #(cast, effects)
      }
    Some(_), _ | None, None -> #(cast, effects)
  }
}

/// Whether the press is the release of a ChargeRelease threshold: the client has
/// resolved it through the open threshold before any caster check, so a held press
/// does not refuse it (`0x1403bfd60`).
fn is_release(resolution resolution: Resolution) -> Bool {
  case resolution.stage {
    Some(_) -> resolution.ability.method == spell_plan.ChargeRelease
    None -> False
  }
}

fn verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  now_ms now_ms: Int,
  is_release is_release: Bool,
  target_subject target_subject: Option(prerequisite.Subject),
) -> Verdict {
  let refused_life = spell_plan.refused_life(spell:, dead: caster.dead)
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesDead),
    return: Refuse(result: cast_result.CasterCannotBeDead),
  )
  use <- bool.guard(
    when: refused_life == Some(spell_plan.RefusesLiving),
    return: Refuse(result: cast_result.from_value(
      cast_state.caster_must_be_dead,
    )),
  )
  use <- bool.guard(
    when: option.is_some(cast.held) && !is_release,
    return: Refuse(result: cast_result.SpellAlreadyCasting),
  )
  use <- bool.guard(
    when: !cast_cost.is_built(spell.method),
    return: NotBuilt(
      result: cast_result.IllegalSpellCast,
      why: "is not cast by a method that is built",
      issue: SpellsIssue,
    ),
  )
  use <- bool.guard(
    when: cast_cost.casting(cast) && !spell.ignores_casting,
    return: case time_left_of_current_cast(cast:, now_ms:) {
      Some(left_ms) if left_ms <= cast_state.queue_window_ms -> HoldForCast
      Some(_) | None -> Refuse(result: cast_result.SpellAlreadyCasting)
    },
  )
  use <- cast_cost.refuse_when(cast_cost.restricted(cast:, spell:))
  let #(global_left, own_left) =
    cast_cost.cooldown_left_ms(cast:, spell:, now_ms:)
  use <- bool.guard(
    when: global_left > cast_state.queue_window_ms,
    return: Refuse(result: cast_result.SpellGlobalCooldown),
  )
  use <- bool.guard(
    when: own_left > cast_state.queue_window_ms,
    return: Refuse(result: cast_result.SpellCooldown),
  )
  case
    requirement_refusal(cast:, caster:, spell:),
    cast_cost.costs_paid(
      costs: spell.costs,
      resources: cast_cost.unreserved(cast:, resources: caster.resources),
    )
  {
    Some(refusal), _ -> refusal
    None, Error(Unpaid(result:)) ->
      Refuse(result: cast_result.from_value(result))
    None, Error(Unheld(result:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost of a vital the server does not hold",
        issue: SpellsIssue,
      )
    None, Error(UnreadSpend(result:, emm_id:)) ->
      NotBuilt(
        result: cast_result.from_value(result),
        why: "has an innate cost spent by the EMM id "
          <> int.to_string(emm_id)
          <> ", which the server does not read",
        issue: SpellsIssue,
      )
    None, Ok(paid) ->
      case
        cast_cost.lacks_the_weapon(spell:, caster:),
        int.max(global_left, own_left)
      {
        True, _ -> Refuse(result: cast_result.WeaponSlot)
        False, 0 ->
          cast_conditions(cast:, caster:, spell:, paid:, target_subject:)
        False, wait_ms -> Hold(wait_ms:)
      }
  }
}

/// What the spell's caster requirements make of the press: the refusal for the first the
/// caster fails and its waiver does not pass (`0x1403b1780`), none when each is met or
/// waived. A waiver the server cannot read refuses with the requirement's result, as
/// not built (the server's choice, as for a cost in a vital it does not hold).
fn requirement_refusal(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> Option(Verdict) {
  list.find_map(spell.requirements, fn(requirement) {
    case cast_cost.meets(requirement:, resources: caster.resources) {
      True -> Error(Nil)
      False ->
        case waiver_verdict(cast:, caster:, spell:) {
          prerequisite.Passes -> Error(Nil)
          prerequisite.Fails ->
            Ok(Refuse(result: cast_result.from_value(requirement.result)))
          prerequisite.NotRead(prerequisite_type:) ->
            Ok(NotBuilt(
              result: cast_result.from_value(requirement.result),
              why: "has a caster requirement whose waiver is a condition of the PrerequisiteType "
                <> int.to_string(prerequisite_type)
                <> ", which the server does not read",
              issue: PrerequisitesIssue,
            ))
        }
    }
  })
  |> option.from_result
}

/// What the spell's waiver makes of a failed requirement: the waiver's prerequisite
/// checked against the caster, and a spell that has none fails (`0x1403b1780`).
fn waiver_verdict(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
) -> prerequisite.Verdict {
  case spell.caster_cast {
    spell_plan.RequirementWaiver(prerequisite: waiver) ->
      prerequisite.check(
        prerequisite: waiver,
        subject: subject_of(cast:, caster:),
      )
    spell_plan.CastGate(..) | spell_plan.NoCasterCast -> prerequisite.Fails
  }
}

/// The press that passed every other check, now against the spell's own cast
/// conditions in the client's order: CasterCast, then TargetCast (`0x1403ace00`). The
/// caster is both units of each check unless the press names a target: the client makes
/// the caster the target of every spell it presses that takes none (the cast module's doc,
/// "The target"), and `target_subject` is the unit a press of an aimed spell names, which
/// TargetCast reads as its first unit. A condition the server cannot read, a type it does
/// not read or a roll (a press draws none), refuses with the check's result as not built.
fn cast_conditions(
  cast cast: State,
  caster caster: Caster,
  spell spell: Spell,
  paid paid: Paid,
  target_subject target_subject: Option(prerequisite.Subject),
) -> Verdict {
  let caster_gate = case spell.caster_cast {
    spell_plan.CastGate(prerequisite: gate) -> Some(gate)
    spell_plan.RequirementWaiver(..) | spell_plan.NoCasterCast -> None
  }
  use <- bool.guard(
    when: option.is_none(caster_gate) && option.is_none(spell.target_cast),
    return: Accept(paid:),
  )
  let subject = subject_of(cast:, caster:)
  case
    cast_cost.condition_verdict(
      gate: caster_gate,
      subject:,
      result: cast_result.PrereqCasterCast,
    )
  {
    Some(refusal) -> refusal
    None ->
      case
        cast_cost.condition_verdict(
          gate: spell.target_cast,
          subject: option.unwrap(target_subject, subject),
          result: cast_result.PrereqTargetCast,
        )
      {
        Some(refusal) -> refusal
        None -> Accept(paid:)
      }
  }
}

/// The time the caster's current cast has left, in milliseconds, from its start
/// and its duration (`cast.press_queue`); none when it has no end of its own,
/// such as a charge held until its release, or an interaction whose bar has run and
/// whose answer is still out.
fn time_left_of_current_cast(
  cast cast: State,
  now_ms now_ms: Int,
) -> Option(Int) {
  use cast_id <- option.then(cast.current)
  use live <- option.then(dict.get(cast.casts, cast_id) |> option.from_result)
  let bar_running = go_waits(cast:, cast_id:)
  case live.interaction {
    AwaitingAnswer if !bar_running -> None
    AwaitingAnswer | NoInteraction | AnswerSucceeded ->
      spell_plan.duration_ms(spell: live.spell)
      |> option.map(fn(duration_ms) {
        int.max(0, live.started_ms + duration_ms - now_ms)
      })
  }
}

/// Whether a live cast waits for the answer of its interaction, with or without a bar.
fn answer_is_out(cast cast: State) -> Bool {
  list.any(dict.values(cast.casts), fn(live) {
    case live.interaction {
      AwaitingAnswer -> True
      NoInteraction | AnswerSucceeded -> False
    }
  })
}

fn cancelled(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  now now: Now,
) -> Result(#(State, List(Effect)), Refusal) {
  use cancel <- result.try(
    cancel_cast.decode(body)
    |> client_connection.decoded(message_id: cancel_cast.message_id)
    |> result.map_error(NotDecoded),
  )
  let reason = cast_result.to_value(cancel.reason)
  use <- bool.guard(
    when: !{
      { reason == 6 || reason == 11 }
      && cancel.field_3 == 1
      || reason == 0
      && cancel.field_3 == 0
    },
    return: Error(UnknownCancel(reason:, bit: cancel.field_3)),
  )
  // A cancel is the player's intent to stop: the cast it names ends the hold that
  // started it (the server's choice), so nothing restarts or fires after it.
  let #(cast, stopped) = stop_holding_cast(cast:, cast_id: cancel.cast_id)
  let #(cast, effects) =
    cancelling(cast:, cancel:, caster:, now_ms: now.monotonic_ms)
  Ok(#(cast, list.append(stopped, effects)))
}

/// The client's 0x805, the answer of the interaction an activate cast of castMethod 5
/// opened (`opcode.0x805.fields`): 3 says it began and changes nothing; 1 sends the go
/// at once, cancelling the go that waited for the cast time; 0 and 2 fail the cast with 146
/// (ClientSideInteractionFail), which ends it with no go. An answer for a cast that is not
/// live is dropped, since the client sends 0 when a finish closes its window
/// (`opcode.0x7fe.csi`); one for a live cast that waits for no answer, one that names
/// another spell or a result the client never sends is refused.
fn answered(
  cast cast: State,
  body body: BitArray,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> Result(#(State, List(Effect)), Refusal) {
  use answer <- result.try(
    client_side_interaction_result.decode(body)
    |> client_connection.decoded(
      message_id: client_side_interaction_result.message_id,
    )
    |> result.map_error(NotDecoded),
  )
  let cast_id = answer.cast_id
  use <- bool.guard(
    when: interaction_result.to_value(answer.result) > 3,
    return: Error(
      UnknownAnswer(result: interaction_result.to_value(answer.result)),
    ),
  )
  case dict.get(cast.casts, cast_id) {
    Error(Nil) ->
      Ok(
        #(cast, [
          Log(
            level: LogDebug,
            text: "the client answered the interaction of the cast "
              <> int.to_string(cast_id)
              <> ", which is not live",
          ),
        ]),
      )
    Ok(live) ->
      case live.interaction {
        AwaitingAnswer -> answer_taken(cast:, caster:, now_ms:, answer:, live:)
        NoInteraction | AnswerSucceeded -> Error(NoInteractionWaits(cast_id:))
      }
  }
}

/// The answer of a live cast that waits for one, once its spell is the one it names.
fn answer_taken(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  answer answer: client_side_interaction_result.ClientSideInteractionResult,
  live live: Live,
) -> Result(#(State, List(Effect)), Refusal) {
  let cast_id = answer.cast_id
  let expected = live.spell.spell4_base_id.value + 1
  use <- bool.guard(
    when: answer.spell4_base_id_plus_one != expected,
    return: Error(WrongAnswerSpell(
      cast_id:,
      sent: answer.spell4_base_id_plus_one,
      expected:,
    )),
  )
  case answer.result {
    interaction_result.Started ->
      Ok(
        #(cast, [
          Log(
            level: LogDebug,
            text: "the client's interaction of the cast "
              <> int.to_string(cast_id)
              <> " began",
          ),
        ]),
      )
    interaction_result.Other(..) ->
      Error(UnknownAnswer(result: interaction_result.to_value(answer.result)))
    interaction_result.Succeeded -> {
      let succeeded = Live(..live, interaction: AnswerSucceeded)
      let cast =
        State(..cast, casts: dict.insert(cast.casts, cast_id, succeeded))
      let #(cast, cancelled) =
        cast_state.cancel_timers(cast:, matching: fn(due) {
          due == Go(cast_id:, phase: 0)
        })
      let #(cast, going) = asked(cast:, caster:, now_ms:, cast_id:, phase: 0)
      Ok(#(cast, list.append(cancelled, going)))
    }
    interaction_result.Failed | interaction_result.CancelledBeforeStart ->
      Ok(persistence_end(
        cast:,
        caster:,
        now_ms:,
        cast_id:,
        result: cast_result.ClientSideInteractionFail,
      ))
  }
}

/// Whether the cast's go timer is still to fire: the cast time has not run.
fn go_waits(cast cast: State, cast_id cast_id: Int) -> Bool {
  list.any(dict.values(cast.timers), fn(due) { due == Go(cast_id:, phase: 0) })
}

/// The hold whose last cast is `cast_id` ends.
fn stop_holding_cast(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case cast.holding {
    Some(Holding(last_cast: Some(last), ..)) if last == cast_id ->
      stop_holding(cast:)
    Some(_) | None -> #(cast, [])
  }
}

/// What a cancel the client may send ends: an open charge with its threshold, or
/// a live cast.
fn cancelling(
  cast cast: State,
  cancel cancel: CancelCast,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let reason = cast_result.to_value(cancel.reason)
  case reason == 0, open_charge_of(cast:, cast_id: cancel.cast_id) {
    True, None -> #(State(..cast, current: None), [
      Log(
        level: LogDebug,
        text: "the client ended the threshold of the cast "
          <> int.to_string(cancel.cast_id)
          <> ", which is not open",
      ),
    ])
    True, Some(threshold) | False, Some(threshold) ->
      // The client clears the player's current cast before it sends, whatever cast
      // that is (`cast.current_cast`); the base cast of the charge ends with the
      // threshold.
      close_threshold(
        cast: State(..cast, current: None),
        ability: threshold.ability,
        now_ms:,
      )
    False, None -> {
      let cast = State(..cast, current: None)
      case dict.get(cast.casts, cancel.cast_id) {
        Error(Nil) -> #(cast, [
          Log(
            level: LogDebug,
            text: "the client ended the cast "
              <> int.to_string(cancel.cast_id)
              <> ", which is not live",
          ),
        ])
        Ok(live) ->
          end_live_cast(cast:, caster:, cast_id: cancel.cast_id, live:, now_ms:)
      }
    }
  }
}

/// A live cast the client cancelled stops: its waiting go and finish timers are
/// cancelled and it ends as after its last go (`finish_or_linger`): a cancel ends no
/// buff, so a cast that holds a node with life left lingers. A cast of
/// `EndsStealthAfterLastGo` that stops after at least one go and before its last ends
/// the other casts' stealth as it stops, since the goes that ran applied their effects;
/// one that stops before any go keeps it (`Spell4.spellCastStealthChange.break`; the
/// server's choice for the stop, the client giving no case). A death or leaving drops
/// every source already, so a 0x801 is the only stop that reaches this.
fn end_live_cast(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = stop_pending(cast:, cast_id:)
  let #(cast, finished) = finish_or_linger(cast:, cast_id:, live:, now_ms:)
  let stopped_early =
    live.spell.stealth_change == spell_plan.EndsStealthAfterLastGo
    && live.gone > 0
    && live.gone < spell_plan.go_count(spell: live.spell)
  let #(cast, broken) = case stopped_early {
    True ->
      stealth_ended(
        cast:,
        caster:,
        sources: other_casts_sources(cast:, cast_id:),
        now_ms:,
      )
    False -> #(cast, [])
  }
  #(cast, list.flatten([cancels, finished, broken]))
}

/// The stealth sources held by casts other than `cast_id`: a cast's own sources are
/// never ended by its own stealth change.
fn other_casts_sources(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(unit_properties.Source) {
  list.filter(dict.keys(cast.stealth), fn(source) { source.cast_id != cast_id })
}

/// The go and finish timers a live cast waits on, cancelled.
fn stop_pending(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      Go(cast_id: waiting, ..) | Finish(cast_id: waiting) -> waiting == cast_id
      StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | ModifierStart(..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> False
    }
  })
}

/// The open threshold whose base cast is `cast_id`: the 32-bit value the 0x816
/// carried, which the client names in a 0x801 (`opcode.0x816`).
fn open_charge_of(cast cast: State, cast_id cast_id: Int) -> Option(Threshold) {
  dict.values(cast.thresholds)
  |> list.find(fn(threshold) {
    threshold.cast_id == cast_id
    && threshold.ability.method == spell_plan.ChargeRelease
  })
  |> option.from_result
}

/// A timer of the rule fired: a go, a finish, a child cast, the held press or a
/// threshold's time.
pub fn timer_fired(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [])
  released(
    taken: fire(cast:, timer:, caster:, now:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A channel's finish timer fired: the cast ends, or, when a go's strike round is still
/// open, waits for that round, since the go's 0x7f4 comes before the 0x7fe
/// (`cast.channel_sequence`). The go that closes the last round ends it, and the
/// round's deadline bounds the wait (`strike`).
fn finish_fired(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) ->
      case live.gone < spell_plan.go_count(spell: live.spell) {
        True -> #(
          State(
            ..cast,
            casts: dict.insert(
              cast.casts,
              cast_id,
              Live(..live, finish_due: True),
            ),
          ),
          [],
        )
        False -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
      }
  }
}

fn fire(
  cast cast: State,
  timer timer: TimerId,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  case dict.get(cast.timers, timer) {
    Error(Nil) -> #(cast, [])
    Ok(due) -> {
      let cast = State(..cast, timers: dict.delete(cast.timers, timer))
      let now_ms = now.monotonic_ms
      case due {
        Go(cast_id:, phase:) -> asked(cast:, caster:, now_ms:, cast_id:, phase:)
        Tick(cast_id:, ..) -> ticks_due(cast:, caster:, now_ms:, cast_id:)
        Finish(cast_id:) -> finish_fired(cast:, cast_id:, now_ms:)
        StartChild(root:, parent:, proxy:, primary_target:) ->
          start(
            cast:,
            caster:,
            now_ms:,
            spell: proxy.spell,
            root:,
            parent: Some(parent),
            primary_target:,
            client_cast_id: None,
            role: Child,
            spent: None,
            reserved: [],
          )
        NodesEnd(cast_id:) -> {
          let #(cast, ticks) = ticks_due(cast:, caster:, now_ms:, cast_id:)
          let #(cast, ended) = nodes_ended(cast:, cast_id:, now_ms:)
          #(cast, list.append(ticks, ended))
        }
        StateEnd(spell4_id:, unit_id:, state:) -> #(cast, [
          Send(frame: cast_frame.control_logged_frame(
            caster_unit_id: caster.unit_id,
            unit_id:,
            spell4_id:,
            state:,
            removed: True,
          )),
        ])
        ModifierStart(source:, change:) -> #(cast, [
          CasterChangeStarts(source:, change:),
        ])
        ModifierEnd(source:) -> #(cast, [CasterChangeEnds(source:)])
        RestrictionEnd(source:) -> restriction_ended(cast:, source:)
        TargetModifierStart(on:, modifier:, struck_at_ms:) ->
          target_modifier_started(cast:, on:, modifier:, struck_at_ms:)
        ForcedMoveStart(on:, move:, struck_at_ms:) ->
          throw_started(cast:, on:, move:, struck_at_ms:)
        CooldownModifierStarts(source:, modifier:, kept:) ->
          cooldown_applied(cast:, source:, modifier:, kept:, now_ms:)
        CooldownModifierEnds(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          [],
        )
        ProcDue(source:, row:, at:) ->
          proc_due(cast:, caster:, now_ms:, source:, row:, at:)
        RepeatHeld -> #(repeat_fired(cast:, timer:), [])
        StartHeld ->
          case cast.held {
            None -> #(cast, [])
            Some(Held(client_cast_id:, resolution:, ..)) ->
              press_of(
                cast: State(..cast, held: None),
                caster:,
                now_ms:,
                client_cast_id:,
                resolution:,
              )
          }
        WindowEnd(spell4_id:) -> window_ended(cast:, spell4_id:, now_ms:)
        ChargeLevel(spell4_id:, level:) ->
          charge_level_reached(cast:, spell4_id:, level:)
      }
    }
  }
}

/// The delay of a property modifier on a creature ran out: it starts on the creature
/// (`TargetChangeStarts`) and the cast keeps it in `on_creatures` until an end of its
/// node; a cast that has ended since starts nothing.
fn target_modifier_started(
  cast cast: State,
  on on: OnCreature,
  modifier modifier: unit_properties.Modifier,
  struck_at_ms struck_at_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id = on.source.cast_id
  let held = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) -> dict.has_key(holder.nodes, on.unit_id)
    Error(Nil) -> False
  }
  use <- bool.guard(when: !held, return: #(cast, []))
  // A later go of the cast strikes the same creature again: its start replaces the
  // earlier one, which the creature replaces by source too.
  let started =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.filter(fn(kept) {
      kept.unit_id != on.unit_id || kept.source != on.source
    })
  #(
    State(
      ..cast,
      on_creatures: dict.insert(
        cast.on_creatures,
        cast_id,
        list.append(started, [on]),
      ),
    ),
    [
      TargetChangeStarts(
        unit_id: on.unit_id,
        life: on.life,
        struck_at_ms:,
        source: on.source,
        modifier:,
      ),
    ],
  )
}

/// The property modifiers the cast `cast_id` holds on the creatures `ending` names end:
/// each that started is told ended once and forgotten, and each that still waits for
/// its delay has its timer cancelled and is told nothing. A modifier already ended is
/// not told again.
fn creature_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: list.contains(unit_ids, _))
}

/// Every property modifier the cast `cast_id` holds on a creature ends, as a persistence
/// that stops holding destroys all its nodes.
fn creature_modifiers_all_ended(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  creatures_ended(cast:, cast_id:, ending: fn(_) { True })
}

fn creatures_ended(
  cast cast: State,
  cast_id cast_id: Int,
  ending ending: fn(Int) -> Bool,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case target_start_of(due:) {
        Ok(waiting) ->
          waiting.source.cast_id == cast_id && ending(waiting.unit_id)
        Error(Nil) -> False
      }
    })
  let #(ended, kept) =
    dict.get(cast.on_creatures, cast_id)
    |> result.unwrap([])
    |> list.partition(fn(on) { ending(on.unit_id) })
  let on_creatures = case kept {
    [] -> dict.delete(cast.on_creatures, cast_id)
    [_, ..] -> dict.insert(cast.on_creatures, cast_id, kept)
  }
  #(
    State(..cast, on_creatures:),
    list.append(
      cancels,
      list.map(ended, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      }),
    ),
  )
}

/// The round of a go closed with `struck`, the units it named in the order of its
/// selection: the go's 0x7f4 with a target info for each (target flags 0), the
/// 0x7fb of the deflected ones, the spell's own cooldown at its first go, the
/// Proxies of the phase (a Proxy aimed at each struck unit starts one child for each
/// Hit unit and none for a deflect, and none for a Proxy whose gate against the
/// caster does not pass) and the finish after the last go. A cast that is no longer
/// live, because the client ended it while the round was open, has no go and writes
/// nothing: the hits stand, and they raise their events (`hit_events`) for the spell of the
/// cast while it is held, else for `spell`, the go's spell as the areas name it by its
/// Spell4 id (`GoAsked.spell4_id`); a go the areas do not name strikes nobody. `poses` are
/// the Hit units' ground points and yaws as the caster's picture holds them when the round
/// closes, by unit id, which a Proxy's target gate reads (`children`); a Hit unit with none is not shown any more. `indexes` are the
/// checklist indexes their 0x262 carried, by unit id, which a type 94 condition of that gate
/// reads; a unit with none has no creature in the check. `units` are what each unit is, by
/// unit id (`prerequisite.FirstUnit`), which a type 38 condition of that gate reads; a unit
/// with none is unknown to the check. `rolls` are the
/// rolls the go's type 37 conditions take (`rolls_needed`), in the order the conditions
/// are checked. `gates_passed` are the effect ids of the gates each struck unit passed, by unit
/// id (genesis_prime/game/strike `Went`): a go row with a gate on the struck creature
/// (`spell_plan.StruckGate`) starts and is listed on a unit only when that unit's entry lists the
/// row, whichever part of the row's aim names the unit, the primary target included, and
/// whatever the round's outcome for it: a unit that deflected still has its entry, and a unit
/// that refused or never answered has none, so a gated row applies on it never. A row with no
/// gate is unaffected.
pub fn went(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  cast_id cast_id: Int,
  phase phase: Int,
  spell asked_spell: Result(Spell, Nil),
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  let own =
    cast_state.holder_of(cast:, cast_id:)
    |> result.map(fn(holder) { holder.spell })
    |> result.lazy_or(fn() { asked_spell })
    |> result.map(fn(spell) { hit_events(spell:, struck:) })
    |> result.unwrap([])
  use <- settled(cast:, own:)
  released(
    taken: go(
      cast:,
      caster:,
      now_ms: now.monotonic_ms,
      cast_id:,
      phase:,
      struck:,
      gates_passed:,
      poses:,
      indexes:,
      units:,
      rolls:,
    ),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

/// A go of a live cast is asked: its first go pays the cast's reserved costs, then
/// the connection selects its targets and strikes them, and answers with `went` when
/// the round closes. A cast that is not live has no go, and an activate cast of
/// castMethod 5 has none until the client has answered 1 (`answered` asks again).
fn asked(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(Live(interaction: AwaitingAnswer, ..)) -> #(cast, [])
    Ok(live) -> {
      // The first go pays what the accept reserved as its strike begins: creatures
      // apply the round's hits as soon as they are told, so they are always paid for,
      // and the go's gates and gains read the paid caster (the server's choice: the
      // order at one go is not recorded).
      let reserved = live.reserved
      let live = Live(..live, reserved: [])
      let cast = State(..cast, casts: dict.insert(cast.casts, cast_id, live))
      case live.activation {
        // An activate cast selects no targets: its go names the activated unit alone.
        Some(_) -> {
          let #(cast, going) =
            go(
              cast:,
              caster:,
              now_ms:,
              cast_id:,
              phase:,
              struck: [],
              gates_passed: dict.new(),
              poses: dict.new(),
              indexes: dict.new(),
              units: dict.new(),
              rolls: [],
            )
          #(cast, list.append(cast_cost.paying(payments: reserved), going))
        }
        None -> #(
          cast,
          list.append(cast_cost.paying(payments: reserved), [
            Strike(asked: GoAsked(
              cast_id:,
              phase:,
              spell4_id: live.spell.spell4_id,
              primary_target: live.primary_target,
              spent: live.spent,
            )),
          ]),
        )
      }
    }
  }
}

/// The nodes of the cast set, wherever the cast is.
fn with_nodes(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
) -> State {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      State(
        ..cast,
        casts: dict.insert(cast.casts, cast_id, Live(..live, nodes:)),
      )
    Error(Nil), Ok(lingering) ->
      State(
        ..cast,
        lingering: dict.insert(
          cast.lingering,
          cast_id,
          Lingering(..lingering, nodes:),
        ),
      )
    Error(Nil), Error(Nil) -> cast
  }
}

/// The nodes whose life is over at the time, and the others, each with its unit id. A
/// node whose unit has a tick round open is kept past its end until the round closes
/// (`ticked`), so its 0x811 or the cast's 0x7fe follows the tick's 0x7f8.
fn ended_and_kept(
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> #(List(#(Int, lasting.Node)), List(#(Int, lasting.Node))) {
  dict.to_list(nodes)
  |> list.partition(fn(entry) {
    life_over(life: { entry.1 }.life, now_ms:)
    && !tick_round_open(ticking:, unit_id: entry.0)
  })
}

/// Whether a tick round of the cast on the unit is open.
fn tick_round_open(
  ticking ticking: Dict(TickKey, Ticking),
  unit_id unit_id: Int,
) -> Bool {
  dict.fold(ticking, False, fn(open, key, row) {
    open || { key.unit_id == unit_id && row.open > 0 }
  })
}

/// The periodic rows of the cast set, wherever the cast is.
fn with_ticking(
  cast cast: State,
  cast_id cast_id: Int,
  ticking ticking: Dict(TickKey, Ticking),
) -> State {
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ ->
      State(
        ..cast,
        casts: dict.insert(cast.casts, cast_id, Live(..live, ticking:)),
      )
    Error(Nil), Ok(lingering) ->
      State(
        ..cast,
        lingering: dict.insert(
          cast.lingering,
          cast_id,
          Lingering(..lingering, ticking:),
        ),
      )
    Error(Nil), Error(Nil) -> cast
  }
}

/// The `Tick` timers of the cast whose row on its unit `matching` accepts, cancelled.
fn tick_timers_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
  matching matching: fn(TickKey) -> Bool,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      Tick(cast_id: waiting, effect_id:, unit_id:, ..) ->
        waiting == cast_id && matching(TickKey(unit_id:, effect_id:))
      Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | ModifierStart(..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..) -> False
    }
  })
}

/// The earliest node of the cast `cast_id` has ended, live or lingering: the nodes
/// whose life is over are dropped and written 0x811, and the timer starts again for the
/// next end. A lingering cast left with no node ends with its 0x7fe instead. A cast
/// that holds nothing any more has no frame. The ticks of an ended node stop with it.
fn nodes_ended(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(ended, kept) =
        ended_and_kept(nodes: holder.nodes, ticking: holder.ticking, now_ms:)
      case ended {
        [] -> rearmed(cast:, cast_id:, now_ms:)
        [_, ..] -> {
          let #(cast, ticks) =
            ticks_dropped_on(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, started) =
            cooldowns_started_at_node_end(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: cast_state.sorted_units(ended),
              now_ms:,
            )
          let #(cast, healed) =
            heals_landed_at_node_end(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, modifiers) =
            caster_modifiers_ended(
              cast:,
              cast_id:,
              spell: holder.spell,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, on_creatures) =
            creature_modifiers_ended(
              cast:,
              cast_id:,
              unit_ids: cast_state.sorted_units(ended),
            )
          let #(cast, left) =
            nodes_left(
              cast:,
              cast_id:,
              holder:,
              nodes: dict.from_list(kept),
              now_ms:,
            )
          #(
            cast,
            list.flatten([
              ticks,
              nodes_ended_frames(cast_id:, holder:, ended:, kept:),
              started,
              healed,
              modifiers,
              on_creatures,
              left,
            ]),
          )
        }
      }
    }
  }
}

/// The ticks of the cast `cast_id` due at the time fire, each due tick of each row, a
/// connection fallen behind included, earliest first and at one time in unit and row id
/// order: a damage row asks its unit for the tick (`TickStrike`), whose 0x7f8 waits for
/// `ticked`; a heal row writes its 0x7f8 to the caster, tells the audience
/// (genesis_prime/client_connection `CastTicked`) and heals the caster
/// (`CasterChangeStarts`), reading the vitals the heal ticks before it in the step left,
/// and heals nothing on a dead caster. Then each row that fired has its next tick armed,
/// or none after its last (genesis_prime/game/ticking `next_tick`). Any tick timer of the
/// cast fires every tick due with it, so ticks due together keep that order whichever
/// timer fires first.
fn ticks_due(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, landed, fired) =
    due_ticks_landed(
      cast:,
      caster:,
      now_ms:,
      cast_id:,
      landed: [],
      fired: set.new(),
    )
  let #(cast, armed) =
    set.to_list(fired)
    |> list.sort(by_tick_key)
    |> list.fold(#(cast, []), fn(so_far, key) {
      let #(cast, effects) = so_far
      let #(cast, more) = next_tick_armed(cast:, now_ms:, cast_id:, key:)
      #(cast, list.append(effects, more))
    })
  #(cast, list.append(landed, armed))
}

/// The earliest due tick of the cast fires, again until none is due, with the caster's
/// vitals as each heal tick leaves them; the rows that fired are gathered.
fn due_ticks_landed(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  landed landed: List(Effect),
  fired fired: Set(TickKey),
) -> #(State, List(Effect), Set(TickKey)) {
  let due = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) ->
      earliest_due(ticking: holder.ticking, now_ms:)
      |> result.map(fn(due) { #(holder, due) })
    Error(Nil) -> Error(Nil)
  }
  case due {
    Error(Nil) -> #(cast, landed, fired)
    Ok(#(holder, #(key, tick))) -> {
      let #(cast, caster, more) =
        tick_landed(cast:, caster:, cast_id:, holder:, key:, tick:)
      due_ticks_landed(
        cast:,
        caster:,
        now_ms:,
        cast_id:,
        landed: list.append(landed, more),
        fired: set.insert(fired, key),
      )
    }
  }
}

/// The row and the tick due earliest at the time, at one time the lowest unit id and
/// then row id; none when no tick is due.
fn earliest_due(
  ticking rows: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> Result(#(TickKey, Int), Nil) {
  dict.to_list(rows)
  |> list.filter_map(fn(entry) {
    let #(key, row) = entry
    use next <- result.try(option.to_result(
      ticking.next_tick(schedule: row.schedule, tick: row.tick),
      Nil,
    ))
    let at_ms =
      ticking.tick_at_ms(
        schedule: row.schedule,
        from_ms: row.from_ms,
        tick: next,
      )
    case at_ms <= now_ms {
      True -> Ok(#(at_ms, key, next))
      False -> Error(Nil)
    }
  })
  |> list.sort(fn(first, second) {
    int.compare(first.0, second.0)
    |> order.break_tie(by_tick_key(first.1, second.1))
  })
  |> list.first
  |> result.map(fn(due) { #(due.1, due.2) })
}

/// Rows in unit id order, then row id order.
fn by_tick_key(first: TickKey, second: TickKey) -> order.Order {
  int.compare(first.unit_id, second.unit_id)
  |> order.break_tie(int.compare(first.effect_id.value, second.effect_id.value))
}

/// Tick `tick` of the row `key` of the cast fires (`ticks_due`), with the caster as the
/// heal ticks before it left it.
fn tick_landed(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  holder holder: Holder,
  key key: TickKey,
  tick tick: Int,
) -> #(State, Caster, List(Effect)) {
  case dict.get(holder.ticking, key) {
    Error(Nil) -> #(cast, caster, [])
    Ok(row) -> {
      let #(row, caster, landed) = case row.kind {
        DamageTick(blow:) -> #(
          Ticking(..row, tick:, open: row.open + 1),
          caster,
          [
            TickStrike(asked: TickAsked(
              cast_id:,
              spell4_id: holder.spell.spell4_id,
              effect_id: key.effect_id,
              unit_id: key.unit_id,
              life: row.life,
              go: row.go,
              tick:,
              blow:,
            )),
          ],
        )
        HealTick(vital:, formula:) -> {
          let #(caster, healed) =
            healed_by_tick(
              caster:,
              cast_id:,
              effect_id: key.effect_id,
              audience: holder.audience,
              vital:,
              formula:,
            )
          #(Ticking(..row, tick:), caster, healed)
        }
      }
      #(
        with_ticking(
          cast:,
          cast_id:,
          ticking: dict.insert(holder.ticking, key, row),
        ),
        caster,
        landed,
      )
    }
  }
}

/// The row `key`'s tick timer cancelled and its next tick armed, none after its last.
fn next_tick_armed(
  cast cast: State,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  key key: TickKey,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(other) { other == key })
  let next = case cast_state.holder_of(cast:, cast_id:) {
    Ok(holder) ->
      case dict.get(holder.ticking, key) {
        Ok(row) ->
          ticking.next_tick(schedule: row.schedule, tick: row.tick)
          |> option.map(fn(after) { #(row, after) })
        Error(Nil) -> None
      }
    Error(Nil) -> None
  }
  case next {
    None -> #(cast, cancels)
    Some(#(row, after)) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: Tick(
            cast_id:,
            effect_id: key.effect_id,
            unit_id: key.unit_id,
            tick: after,
          ),
          after_ms: int.max(
            0,
            ticking.tick_at_ms(
              schedule: row.schedule,
              from_ms: row.from_ms,
              tick: after,
            )
              - now_ms,
          ),
        )
      #(cast, list.append(cancels, [start]))
    }
  }
}

/// A heal tick on the caster: its 0x7f8 with the heal's description, told to the
/// audience, then the heal, the formula read for the caster as it is at the tick and
/// split by the room its vitals have then (`split_of`); the caster comes back with the
/// heal's split added to its vitals, for a heal tick due with it. A dead caster is healed
/// nothing and shown nothing.
fn healed_by_tick(
  caster caster: Caster,
  cast_id cast_id: Int,
  effect_id effect_id: Spell4EffectsId,
  audience audience: Set(ConnectionId),
  vital vital: effect_kind.Vital,
  formula formula: damage.Formula,
) -> #(Caster, List(Effect)) {
  use <- bool.guard(when: caster.dead, return: #(caster, []))
  let amount =
    damage.amount_on_caster(formula:, caster: cast_heal.on_caster_of(caster:))
  let split = cast_heal.split_of(vital:, amount:, caster:)
  let healed = Healed(effect_id:, vital:, delay_ms: 0, amount:, split:)
  #(
    Caster(
      ..caster,
      vitals: damage.Vitals(
        ..caster.vitals,
        health: caster.vitals.health + split.health,
        shield: caster.vitals.shield + split.shield,
      ),
    ),
    list.flatten([
      tick_effects(
        tick: SpellEffectTick(
          cast_id:,
          spell4_effects_id: effect_id.value,
          unit_id: caster.unit_id,
          descriptions: [cast_heal.heal_description(healed:)],
        ),
        audience:,
      ),
      [
        CasterChangeStarts(
          source: unit_properties.Source(cast_id:, effect_id:),
          change: Heal(vital:, amount:),
        ),
      ],
    ]),
  )
}

/// 0x7f8 to the caster and told to the audience.
fn tick_effects(
  tick tick: SpellEffectTick,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  [
    Send(frame: cast_frame.ticked_frame(tick:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastTicked(tick:))
    })
  ]
}

/// A tick's strike round closed (genesis_prime/game/strike `Ticked`): a landed tick
/// writes the 0x7f8 to the caster and tells the audience `CastTicked`, and a killing one
/// then drops the unit's ticks; a deflected or immune tick writes nothing and the ticks
/// go on; a refused tick or one left out at the deadline (`None`) writes nothing and
/// drops the unit's ticks. A tick whose row was dropped while its round was open, or
/// whose schedule a later go started again, writes nothing. A node end that waited for
/// the round goes on (`nodes_ended`).
pub fn ticked(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
  asked asked: TickAsked,
  struck struck: Option(Struck),
) -> #(State, List(Effect)) {
  // A landed tick of a row the cast still holds raises the events of a hit (a guess: no
  // source says a periodic damage tick is a hit for a Proc).
  let own = case
    struck,
    cast_state.holder_of(cast:, cast_id: asked.cast_id)
    |> result.try(fn(holder) {
      dict.get(
        holder.ticking,
        TickKey(unit_id: asked.unit_id, effect_id: asked.effect_id),
      )
      |> result.map(fn(_) { holder })
    })
  {
    Some(one), Ok(holder) -> hit_events(spell: holder.spell, struck: [one])
    _, _ -> []
  }
  use <- settled(cast:, own:)
  released(
    taken: tick_closed(cast:, now_ms: now.monotonic_ms, asked:, struck:),
    caster:,
    now_ms: now.monotonic_ms,
  )
  |> continued(caster:, now_ms: now.monotonic_ms)
}

fn tick_closed(
  cast cast: State,
  now_ms now_ms: Int,
  asked asked: TickAsked,
  struck struck: Option(Struck),
) -> #(State, List(Effect)) {
  let cast_id = asked.cast_id
  let key = TickKey(unit_id: asked.unit_id, effect_id: asked.effect_id)
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) ->
      case dict.get(holder.ticking, key) {
        Error(Nil) -> #(cast, [])
        Ok(row) -> {
          let cast =
            with_ticking(
              cast:,
              cast_id:,
              ticking: dict.insert(
                holder.ticking,
                key,
                Ticking(..row, open: int.max(0, row.open - 1)),
              ),
            )
          let #(cast, landed) =
            tick_outcome(
              cast:,
              audience: holder.audience,
              row:,
              asked:,
              struck:,
              now_ms:,
            )
          let #(cast, ended) = nodes_ended(cast:, cast_id:, now_ms:)
          #(cast, list.append(landed, ended))
        }
      }
  }
}

/// What a closed tick round of the row does: a hit writes its 0x7f8 to the audience,
/// whichever go's schedule asked it, since the unit took the damage and its health news
/// goes out, and one that kills drops the unit's ticks; a deflect or an immunity writes
/// nothing; no answer for a round of the row's current schedule (the unit is gone, or
/// refused the tick for a life it no longer has) drops the unit's ticks and ends its node
/// now (`node_ended_now`), so the cast's 0x811 or 0x7fe goes when the round closes. No
/// answer for a round of an earlier schedule does nothing: the later go's own ticks ask
/// the unit again.
fn tick_outcome(
  cast cast: State,
  audience audience: Set(ConnectionId),
  row row: Ticking,
  asked asked: TickAsked,
  struck struck: Option(Struck),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast_id = asked.cast_id
  case struck, row.go == asked.go {
    Some(Hit(descriptions:, ..)), _ -> {
      let written =
        tick_effects(
          tick: SpellEffectTick(
            cast_id:,
            spell4_effects_id: asked.effect_id.value,
            unit_id: asked.unit_id,
            descriptions: list.map(descriptions, fn(description) {
              description.damage
            }),
          ),
          audience:,
        )
      let killed =
        list.any(descriptions, fn(description) {
          description.damage.killed != 0
        })
      use <- bool.guard(when: !killed, return: #(cast, written))
      let #(cast, dropped) =
        ticks_dropped(cast:, cast_id:, unit_id: asked.unit_id)
      #(cast, list.append(written, dropped))
    }
    Some(Deflected(..)), _ | Some(Immune(..)), _ | None, False -> #(cast, [])
    None, True -> {
      let #(cast, dropped) =
        ticks_dropped(cast:, cast_id:, unit_id: asked.unit_id)
      #(
        node_ended_now(cast:, cast_id:, unit_id: asked.unit_id, now_ms:),
        dropped,
      )
    }
  }
}

/// The cast's node on the unit ends at the time, so the node end that follows
/// (`nodes_ended`) drops it with its frames.
fn node_ended_now(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> State {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> cast
    Ok(holder) ->
      case dict.get(holder.nodes, unit_id) {
        Error(Nil) -> cast
        Ok(node) ->
          with_nodes(
            cast:,
            cast_id:,
            nodes: dict.insert(
              holder.nodes,
              unit_id,
              lasting.Node(..node, life: lasting.EndsAt(ms: now_ms)),
            ),
          )
      }
  }
}

/// A go arms the first tick of each periodic row on each unit it reached (`TickingOn`),
/// counted from the go's monotonic time `from_ms`; `go` is which go of the cast it is. A
/// row already ticking on the unit for this cast is armed again from this go, as the
/// client sets its node again, and its earlier schedule's tick timer is cancelled; a
/// round of that schedule still open writes nothing when it closes (`ticked`).
fn ticks_armed(
  cast cast: State,
  cast_id cast_id: Int,
  go go: Int,
  from_ms from_ms: Int,
  rows rows: List(TickingOn),
) -> #(State, List(Effect)) {
  list.fold(rows, #(cast, []), fn(so_far, on) {
    let #(cast, effects) = so_far
    let key = TickKey(unit_id: on.unit_id, effect_id: on.effect_id)
    let #(cast, cancels) =
      tick_timers_cancelled(cast:, cast_id:, matching: fn(other) {
        other == key
      })
    case cast_state.holder_of(cast:, cast_id:) {
      Error(Nil) -> #(cast, list.append(effects, cancels))
      Ok(holder) -> {
        let open = case dict.get(holder.ticking, key) {
          Ok(earlier) -> earlier.open
          Error(Nil) -> 0
        }
        let schedule =
          ticking.within_life(
            schedule: on.schedule,
            longer_of_delay_and_duration: holder.spell.longer_of_delay_and_duration,
          )
        let row =
          Ticking(
            kind: on.kind,
            schedule:,
            go:,
            from_ms:,
            tick: 0,
            open:,
            life: on.life,
          )
        let cast =
          with_ticking(
            cast:,
            cast_id:,
            ticking: dict.insert(holder.ticking, key, row),
          )
        let #(cast, start) = first_tick_armed(cast:, cast_id:, key:, schedule:)
        #(cast, list.flatten([effects, cancels, start]))
      }
    }
  })
}

/// The timer of the row `key`'s first tick, none when no tick lands within its life.
fn first_tick_armed(
  cast cast: State,
  cast_id cast_id: Int,
  key key: TickKey,
  schedule schedule: ticking.Schedule,
) -> #(State, List(Effect)) {
  case ticking.next_tick(schedule:, tick: 0) {
    None -> #(cast, [])
    Some(first) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: Tick(
            cast_id:,
            effect_id: key.effect_id,
            unit_id: key.unit_id,
            tick: first,
          ),
          after_ms: ticking.tick_at_ms(schedule:, from_ms: 0, tick: first),
        )
      #(cast, [start])
    }
  }
}

/// The ticks of the cast on the unit stop with its node: their timers are cancelled
/// and their rows forgotten. Every path that drops a node calls it: a removal of the
/// unit, a type 80 removal, the stack cap and a node's end; a finish, a persistence
/// end, a death and leaving cancel every tick of the cast.
fn ticks_dropped(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(key) {
      key.unit_id == unit_id
    })
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, cancels)
    Ok(holder) -> #(
      with_ticking(
        cast:,
        cast_id:,
        ticking: dict.filter(holder.ticking, fn(key, _) {
          key.unit_id != unit_id
        }),
      ),
      cancels,
    )
  }
}

/// The ticks of the cast on each of the units stop (`ticks_dropped`).
fn ticks_dropped_on(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  list.fold(unit_ids, #(cast, []), fn(so_far, unit_id) {
    let #(cast, effects) = so_far
    let #(cast, more) = ticks_dropped(cast:, cast_id:, unit_id:)
    #(cast, list.append(effects, more))
  })
}

/// Every tick of the cast stops: a finish or a persistence end ends all its nodes.
fn ticks_all_dropped(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    tick_timers_cancelled(cast:, cast_id:, matching: fn(_) { True })
  #(with_ticking(cast:, cast_id:, ticking: dict.new()), cancels)
}

/// What the end of some of a cast's nodes writes: the 0x7fe of a lingering cast left with
/// none, else 0x811 for the units whose node ended, with the cast destroyed on the client
/// when it has no node left and its method is not one the client keeps.
fn nodes_ended_frames(
  cast_id cast_id: Int,
  holder holder: Holder,
  ended ended: List(#(Int, lasting.Node)),
  kept kept: List(#(Int, lasting.Node)),
) -> List(Effect) {
  case holder.lingering && kept == [] {
    True -> finished_effects(cast_id:, audience: holder.audience)
    False ->
      targets_removed_effects(
        cast_id:,
        unit_ids: cast_state.sorted_units(ended),
        audience: holder.audience,
        destroyed: kept == []
          && !keeps_without_target(method: holder.spell.method),
      )
  }
}

/// The cast's nodes after some left: a lingering cast with none left is dropped; any
/// other keeps the nodes it has, with its `NodesEnd` timer started again for them.
fn nodes_left(
  cast cast: State,
  cast_id cast_id: Int,
  holder holder: Holder,
  nodes nodes: Dict(Int, lasting.Node),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case holder.lingering && dict.is_empty(nodes) {
    True -> {
      let #(cast, cancels) = cancel_nodes_end(cast:, cast_id:)
      #(
        passive_cleared(
          cast: State(..cast, lingering: dict.delete(cast.lingering, cast_id)),
          cast_id:,
        ),
        cancels,
      )
    }
    False ->
      rearmed(cast: with_nodes(cast:, cast_id:, nodes:), cast_id:, now_ms:)
  }
}

/// Whether a node's life is over at the time: it ended, or it never had one.
fn life_over(life life: lasting.Life, now_ms now_ms: Int) -> Bool {
  case life {
    lasting.EndsAt(ms:) -> ms <= now_ms
    lasting.NoLife -> True
    lasting.UntilRemoved -> False
  }
}

/// The earliest time a node ends at, none when every node lasts until it is removed
/// or is held by an open tick round on its unit, whose close ends it (`ticked`).
fn earliest_end(
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
) -> Option(Int) {
  list.filter_map(dict.to_list(nodes), fn(entry) {
    let #(unit_id, node) = entry
    case node.life, tick_round_open(ticking:, unit_id:) {
      _, True -> Error(Nil)
      lasting.EndsAt(ms:), False -> Ok(ms)
      lasting.NoLife, False | lasting.UntilRemoved, False -> Error(Nil)
    }
  })
  |> list.reduce(int.min)
  |> option.from_result
}

/// The cast's `NodesEnd` timer, started for its earliest ending node; none when no
/// node ends by time.
fn arm_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
  nodes nodes: Dict(Int, lasting.Node),
  ticking ticking: Dict(TickKey, Ticking),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case earliest_end(nodes:, ticking:) {
    None -> #(cast, [])
    Some(ends_ms) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: NodesEnd(cast_id:),
          after_ms: int.max(0, ends_ms - now_ms),
        )
      #(cast, [start])
    }
  }
}

/// The cast's `NodesEnd` timer cancelled and started again for the nodes it holds
/// now.
fn rearmed(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) = cancel_nodes_end(cast:, cast_id:)
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, cancels)
    Ok(holder) -> {
      let #(cast, armed) =
        arm_nodes_end(
          cast:,
          cast_id:,
          nodes: holder.nodes,
          ticking: holder.ticking,
          now_ms:,
        )
      #(cast, list.append(cancels, armed))
    }
  }
}

/// The `NodesEnd` timers of the cast cancelled.
fn cancel_nodes_end(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      NodesEnd(cast_id: waiting) -> waiting == cast_id
      Go(..)
      | Finish(..)
      | StartChild(..)
      | StateEnd(..)
      | ModifierStart(..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> False
    }
  })
}

/// A unit the caster's client shows is removed from it (a 0x355 for a unit it was
/// shown): the client destroys that unit's nodes then (`0x1404550d0`), so the
/// unit's nodes are dropped from the live and lingering casts, and nothing is
/// written for them; a lingering cast left with no node sends its finish and is
/// dropped, and one that keeps nodes has its `NodesEnd` timer started again. This
/// bounds the casts that linger by the units in sight, so the caster's cast ids
/// (`mint`) cannot run out. A property modifier a dropped cast node held on a creature
/// ends with it (`TargetChangeEnds`), since nothing else would end it.
pub fn unit_removed(
  cast cast: State,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        StateEnd(unit_id: waiting, ..) -> waiting == unit_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ModifierEnd(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | ProcDue(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  list.filter(cast_state.holders(cast:), fn(entry) {
    dict.has_key({ entry.1 }.nodes, unit_id)
  })
  |> list.fold(#(cast, cancels), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(cast_id, holder) = entry
    let nodes = dict.delete(holder.nodes, unit_id)
    let #(cast, ticks) = ticks_dropped(cast:, cast_id:, unit_id:)
    let #(cast, on_creatures) =
      creature_modifiers_ended(cast:, cast_id:, unit_ids: [unit_id])
    let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
    let ends = case holder.lingering && dict.is_empty(nodes) {
      True -> finished_effects(cast_id:, audience: holder.audience)
      False -> []
    }
    #(cast, list.flatten([effects, ticks, on_creatures, left, ends]))
  })
}

/// The player left the world with casts live: every timer is cancelled and nothing is
/// written; each property modifier the casts hold on a creature is told ended
/// (`TargetChangeEnds`), the creature's own, in cast id order.
pub fn left(cast cast: State) -> #(State, List(Effect)) {
  let on_creatures =
    dict.to_list(cast.on_creatures)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      list.map(entry.1, fn(on) {
        TargetChangeEnds(unit_id: on.unit_id, life: on.life, source: on.source)
      })
    })
  #(
    State(
      ..cast,
      casts: dict.new(),
      lingering: dict.new(),
      timers: dict.new(),
      held: None,
      holding: None,
      current: None,
      thresholds: dict.new(),
      cooldowns: cooldown.drop_all(book: cast.cooldowns),
      stealth: dict.new(),
      procs: dict.new(),
      passive: None,
      on_creatures: dict.new(),
      restrictions: dict.new(),
    ),
    list.append(
      list.map(dict.keys(cast.timers), fn(timer) { CancelTimer(timer:) }),
      on_creatures,
    ),
  )
}

/// The caster died: each live cast ends with its timers cancelled and 0x7fe to
/// the caster and the audience that was told its start, in cast id order, and its nodes
/// with it, where a 0x801 lets them linger (`end_live_cast`); then the held press, the hold and every open
/// threshold end, and every other timer is cancelled, as when the player leaves
/// (`left`). The client does not end its own casts when it dies (not read,
/// `0x14045e740`), so the server's 0x7fe is the end its viewers see. Every stealth
/// source drops, and a stealthed caster's `StealthChanged` comes after the casts'
/// 0x7fe, followed by the casts of the procs the death fires: the `Died` procs first,
/// then those for the stealth it ended. The innate passive's cast is the one cast it
/// leaves: it stays live or lingering with its nodes, its modifiers, its pending timers,
/// its stealth sources and its procs, and nothing is written for it
/// (`passive_set_aside`); the delayed fires of its procs are the exception, dropped with
/// their timers cancelled, since the holder they wait for is gone (`proc_fires_dropped`).
pub fn died(
  cast cast: State,
  caster _caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [
    proc.Event(trigger: spell_plan.Died, other_unit: None, spell: None),
  ])
  all_ended(cast:, now:)
}

/// The caster left combat: the combat flag of its life (genesis_prime/game/player_life
/// `CombatLeft`) went off. The only effects are the casts of the procs held for it.
pub fn combat_left(
  cast cast: State,
  caster _caster: Caster,
  now _now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [
    proc.Event(trigger: spell_plan.LeftCombat, other_unit: None, spell: None),
  ])
  #(cast, [])
}

/// Whether some live or lingering cast holds a spell with a persistence column, so
/// `persisted` has something to check: the connection asks before it builds the caster,
/// since most inputs find nothing.
pub fn persists(cast cast: State) -> Bool {
  list.any(cast_state.holders(cast:), fn(entry) {
    has_persistence(spell: { entry.1 }.spell)
  })
}

fn has_persistence(spell spell: Spell) -> Bool {
  option.is_some(spell.caster_persistence)
  || option.is_some(spell.target_persistence)
}

/// The end of an input in the world: each live or lingering cast whose spell's
/// persistence condition no longer holds ends, in cast id order, the lowest first,
/// checked again after each end (it can break another's condition), and a press held
/// for the current cast it cleared starts. The client never evaluates a persistence
/// column (`Spell4.prerequisiteIdCasterPersistence`), so when to check and how to end
/// are the server's: after every input, which is exact and needs no timer. A cast ends
/// with 0x7f9 {cast id, 282 or 283, the caster, 0}, which destroys its nodes and so ends
/// its buff, then the 0x7fe that takes it out of the client's table, and is told to the
/// audience as a finish (`opcode.0x7f9`, `cast.target_node_end`). CasterPersistence
/// (282) is checked before TargetPersistence (283), the caster the first unit and the
/// cast's primary target the second; TargetPersistence is checked only for a cast the
/// caster itself is the target of, since no creature's state is held here. A press held
/// for the current cast it cleared starts, and a held key repeats, as after any input;
/// the casts they start are checked in turn. A condition
/// of a type not read, a roll (none is drawn) and a creature target keep the cast, with
/// one debug line for the spell.
///
/// Gap (#336): the hoverboard's ride 85563 holds Ability Restriction under a persistence
/// of "under 85562" (Prerequisite 41771), and 85562's SummonMount (type 36) is not read,
/// so no node of 85562 is held and the ride ends in the input of its own go: the client
/// is shown 0x87f, 0x7f9 and 0x880 at once, and a press is refused 302 only while the
/// go's own input is taken. The ride closes this.
pub fn persisted(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [])
  let now_ms = now.monotonic_ms
  let #(cast, ended) = persistence_ended(cast:, caster:, now_ms:, done: [])
  let #(cast, effects) =
    released(taken: #(cast, ended), caster:, now_ms:)
    |> continued(caster:, now_ms:)
  // A press the end let start, or a repeat of a held key, starts a cast whose own
  // persistence may already fail.
  let #(cast, more) =
    persistence_ended(
      cast:,
      caster: cast_cost.after_payments(caster:, effects:),
      now_ms:,
      done: [],
    )
  #(cast, list.append(effects, more))
}

/// The casts that fail their persistence ended one at a time, the lowest cast id first,
/// until none fails.
fn persistence_ended(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  done done: List(Effect),
) -> #(State, List(Effect)) {
  let subject = subject_of(cast:, caster:)
  let #(cast, logs, failing) =
    first_failing_persistence(
      cast:,
      caster:,
      subject:,
      holders: cast_state.holders(cast:),
      logs: [],
    )
  case failing {
    None -> #(cast, list.append(done, logs))
    Some(#(cast_id, result)) -> {
      let #(cast, ended) =
        persistence_end(cast:, caster:, now_ms:, cast_id:, result:)
      persistence_ended(
        cast:,
        caster:,
        now_ms:,
        done: list.flatten([done, logs, ended]),
      )
    }
  }
}

/// The first cast, in the order given, whose persistence fails, with its result and the
/// debug lines of the casts checked on the way.
fn first_failing_persistence(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holders holders: List(#(Int, Holder)),
  logs logs: List(Effect),
) -> #(State, List(Effect), Option(#(Int, cast_result.CastResult))) {
  case holders {
    [] -> #(cast, logs, None)
    [#(cast_id, holder), ..rest] -> {
      let #(cast, more, failing) =
        persistence_of(cast:, caster:, subject:, holder:)
      let logs = list.append(logs, more)
      case failing {
        Some(result) -> #(cast, logs, Some(#(cast_id, result)))
        None ->
          first_failing_persistence(
            cast:,
            caster:,
            subject:,
            holders: rest,
            logs:,
          )
      }
    }
  }
}

/// The result a cast's persistence fails with, none when it holds or cannot be read.
fn persistence_of(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  holder holder: Holder,
) -> #(State, List(Effect), Option(cast_result.CastResult)) {
  let spell = holder.spell
  let #(cast, caster_logs, caster_fails) =
    persistence_column(
      cast:,
      spell:,
      result: cast_result.PrereqCasterPersistence,
      gate: spell.caster_persistence,
      subject: prerequisite.Subject(
        ..subject,
        second_unit: Some(holder.primary_target),
      ),
    )
  use <- bool.guard(when: caster_fails, return: #(
    cast,
    caster_logs,
    Some(cast_result.PrereqCasterPersistence),
  ))
  let #(cast, target_logs, target_fails) = case
    holder.primary_target == caster.unit_id
  {
    True ->
      persistence_column(
        cast:,
        spell:,
        result: cast_result.PrereqTargetPersistence,
        gate: spell.target_persistence,
        subject:,
      )
    False ->
      case spell.target_persistence {
        None -> #(cast, [], False)
        Some(_) -> {
          let #(cast, log) =
            logged_once(
              cast:,
              spell:,
              result: cast_result.PrereqTargetPersistence,
              text: "has a target persistence on a creature, whose state this connection does not hold, so it is not checked",
            )
          #(cast, log, False)
        }
      }
  }
  #(cast, list.append(caster_logs, target_logs), case target_fails {
    True -> Some(cast_result.PrereqTargetPersistence)
    False -> None
  })
}

/// One persistence column checked: whether it fails, and the debug line when it cannot
/// be read, once for the spell.
fn persistence_column(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  gate gate: Option(prerequisite.Prerequisite),
  subject subject: prerequisite.Subject,
) -> #(State, List(Effect), Bool) {
  case cast_cost.column_verdict(gate:, subject:) {
    prerequisite.Passes -> #(cast, [], False)
    prerequisite.Fails -> #(cast, [], True)
    prerequisite.NotRead(prerequisite_type:) -> {
      let #(cast, log) =
        logged_once(
          cast:,
          spell:,
          result:,
          text: "has a persistence of the PrerequisiteType "
            <> int.to_string(prerequisite_type)
            <> ", which the server does not read, so its casts go on",
        )
      #(cast, log, False)
    }
  }
}

/// A debug line about the spell's persistence column of this result, unless one was
/// written already on this connection.
fn logged_once(
  cast cast: State,
  spell spell: Spell,
  result result: cast_result.CastResult,
  text text: String,
) -> #(State, List(Effect)) {
  let key = #(spell.spell4_id.value, cast_result.to_value(result))
  use <- bool.guard(
    when: set.contains(cast.persistence_logged, key),
    return: #(cast, []),
  )
  #(
    State(..cast, persistence_logged: set.insert(cast.persistence_logged, key)),
    [
      Log(
        level: LogDebug,
        text: "the cast of Spell4 "
          <> int.to_string(spell.spell4_id.value)
          <> " "
          <> text,
      ),
    ],
  )
}

/// A cast whose persistence failed ends as a death ends one cast: 0x7f9 with the
/// result, its go, finish, tick and NodesEnd timers cancelled, its property modifiers and
/// cooldown effects ended, the current cast cleared when it was this one, an open
/// threshold it is the base cast of closed as a 0x801 closes it, and its 0x7fe to the
/// caster and the audience.
fn persistence_end(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
) -> #(State, List(Effect)) {
  let failure = failed_effect(cast_id:, result:, unit_id: caster.unit_id)
  case dict.get(cast.casts, cast_id), dict.get(cast.lingering, cast_id) {
    Ok(live), _ -> {
      let #(cast, cancels) = stop_pending(cast:, cast_id:)
      let #(cast, ticks) = ticks_all_dropped(cast:, cast_id:)
      let #(cast, nodes) = cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) = effects_ended(cast:, cast_id:, spell: live.spell)
      let #(cast, on_creatures) = creature_modifiers_all_ended(cast:, cast_id:)
      let #(cast, finished) = case open_charge_of(cast:, cast_id:) {
        Some(threshold) ->
          close_threshold(cast:, ability: threshold.ability, now_ms:)
        None -> finish(cast:, cast_id:, live:, now_ms:)
      }
      #(
        cast,
        list.flatten([
          [failure],
          cancels,
          ticks,
          nodes,
          ended,
          on_creatures,
          finished,
        ]),
      )
    }
    Error(Nil), Ok(lingering) -> {
      let #(cast, ticks) = ticks_all_dropped(cast:, cast_id:)
      let cast = State(..cast, lingering: dict.delete(cast.lingering, cast_id))
      let #(cast, nodes) = cancel_nodes_end(cast:, cast_id:)
      let #(cast, ended) =
        effects_ended(cast:, cast_id:, spell: lingering.spell)
      let #(cast, on_creatures) = creature_modifiers_all_ended(cast:, cast_id:)
      #(
        passive_cleared(cast:, cast_id:),
        list.flatten([
          [failure],
          ticks,
          nodes,
          ended,
          on_creatures,
          finished_effects(cast_id:, audience: lingering.audience),
        ]),
      )
    }
    Error(Nil), Error(Nil) -> #(cast, [])
  }
}

/// 0x7f9 for a cast that failed with this result: the bit is the 0 the 0x7fe path passes
/// (`opcode.0x7f9`). The unit is the caster, not the 0 the 0x7fe path passes: FinishCast
/// releases the threshold of a RapidTap cast ended with a result other than 6 or 8 only
/// when the end names another unit (`0x14053e1b0`), and this rule keeps the threshold of a
/// stage it ends open (only a charge's base cast closes its own), so the unit must not be
/// another; the 0x7fe path's result 8 never touches a threshold, which is why 0 is safe
/// there.
fn failed_effect(
  cast_id cast_id: Int,
  result result: cast_result.CastResult,
  unit_id unit_id: Int,
) -> Effect {
  Send(frame: cast_frame.failed_frame(cast_id:, result:, unit_id:))
}

/// The player's innate passive, the plans' spell of this Spell4Base, starts: a cast of
/// the player's own with its caster as root, no parent and its primary target, written
/// as 0x7ff with no 0x7fd, which runs no check of the caster and starts no global
/// cooldown (`Passive`). It starts at each join, alive or dead. A base the plans do not
/// hold is a warning and no cast.
pub fn passive_started(
  cast cast: State,
  caster caster: Caster,
  plans plans: Plans,
  base base: Spell4BaseId,
  now now: Now,
) -> #(State, List(Effect)) {
  case spell_plan.in_plans(plans:, base:) {
    Error(Nil) -> #(cast, [
      Log(
        level: LogWarning,
        text: "the innate passive with Spell4Base "
          <> int.to_string(base.value)
          <> " is in no plan, so it is not started",
      ),
    ])
    Ok(spell) ->
      start(
        cast:,
        caster:,
        now_ms: now.monotonic_ms,
        spell:,
        root: spell.spell4_id,
        parent: None,
        primary_target: caster.unit_id,
        client_cast_id: None,
        role: Passive,
        spent: None,
        reserved: [],
      )
  }
}

/// The caster's casts, press, hold, thresholds and timers ended by its death.
fn all_ended(cast cast: State, now now: Now) -> #(State, List(Effect)) {
  let #(cast, aside) = passive_set_aside(cast:)
  let #(aside, fires_dropped) = proc_fires_dropped(aside:)
  let #(cast, ended) =
    dict.to_list(cast.casts)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.fold(#(cast, []), fn(so_far, entry) {
      let #(cast, effects) = so_far
      let #(cast, cancels) = stop_pending(cast:, cast_id: entry.0)
      let #(cast, more) =
        finish(cast:, cast_id: entry.0, live: entry.1, now_ms: now.monotonic_ms)
      #(cast, list.flatten([effects, cancels, more]))
    })
  // A lingering cast ends with its 0x7fe when its caster dies: the server's choice,
  // since the client has no path that ends a buff on a unit's death
  // (`cast.target_node_end`).
  let lingering_ended =
    dict.to_list(cast.lingering)
    |> list.sort(fn(first, second) { int.compare(first.0, second.0) })
    |> list.flat_map(fn(entry) {
      finished_effects(cast_id: entry.0, audience: { entry.1 }.audience)
    })
  let modifiers_ended = modifiers_pending(cast:)
  let #(cast, cancelled) = left(cast:)
  #(
    passive_restored(cast:, aside:),
    list.flatten([
      fires_dropped,
      ended,
      lingering_ended,
      modifiers_ended,
      cancelled,
    ]),
  )
}

/// The passive's delayed proc fires dropped with the timers of what a death set aside, and
/// their timers cancelled: the holder is gone, so no cast follows for its hit (a fire the
/// death itself makes is armed after this, by the proc pass).
fn proc_fires_dropped(
  aside aside: Option(Aside),
) -> #(Option(Aside), List(Effect)) {
  case aside {
    None -> #(None, [])
    Some(set_aside) -> {
      let #(fires, kept) =
        list.partition(set_aside.timers, fn(entry) {
          case entry.1 {
            ProcDue(..) -> True
            Go(..)
            | Finish(..)
            | NodesEnd(..)
            | Tick(..)
            | ModifierStart(..)
            | ModifierEnd(..)
            | RestrictionEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | TargetModifierStart(..)
            | ForcedMoveStart(..)
            | StartChild(..)
            | StateEnd(..)
            | StartHeld
            | RepeatHeld
            | WindowEnd(..)
            | ChargeLevel(..) -> False
          }
        })
      #(
        Some(Aside(..set_aside, timers: kept)),
        list.map(fires, fn(entry) { CancelTimer(timer: entry.0) }),
      )
    }
  }
}

/// The cast without the passive's cast, timers, stealth sources and procs, and what was
/// taken out, when the passive has a cast.
fn passive_set_aside(cast cast: State) -> #(State, Option(Aside)) {
  case cast.passive {
    None -> #(cast, None)
    Some(id) -> {
      let live = dict.get(cast.casts, id) |> option.from_result
      let lingering = dict.get(cast.lingering, id) |> option.from_result
      let spell4_id = case live, lingering {
        Some(live), _ -> Some(live.spell.spell4_id)
        None, Some(lingering) -> Some(lingering.spell.spell4_id)
        None, None -> None
      }
      let #(timers, rest) =
        dict.to_list(cast.timers)
        |> list.partition(fn(entry) {
          belongs_to_passive(due: entry.1, id:, spell4_id:)
        })
      let #(stealth, others) = split_cast(held: cast.stealth, cast_id: id)
      let #(procs, other_procs) = split_cast(held: cast.procs, cast_id: id)
      case live, lingering {
        None, None -> #(cast, None)
        _, _ -> #(
          State(
            ..cast,
            casts: dict.delete(cast.casts, id),
            lingering: dict.delete(cast.lingering, id),
            timers: dict.from_list(rest),
            stealth: others,
            procs: other_procs,
            on_creatures: dict.delete(cast.on_creatures, id),
          ),
          Some(Aside(
            id:,
            live:,
            lingering:,
            timers:,
            stealth:,
            procs:,
            on_creatures: dict.get(cast.on_creatures, id) |> result.unwrap([]),
          )),
        )
      }
    }
  }
}

/// The cast with what `passive_set_aside` took out put back.
fn passive_restored(cast cast: State, aside aside: Option(Aside)) -> State {
  case aside {
    None -> cast
    Some(Aside(id:, live:, lingering:, timers:, stealth:, procs:, on_creatures:)) ->
      State(
        ..cast,
        on_creatures: case on_creatures {
          [] -> cast.on_creatures
          [_, ..] -> dict.insert(cast.on_creatures, id, on_creatures)
        },
        casts: case live {
          Some(live) -> dict.insert(cast.casts, id, live)
          None -> cast.casts
        },
        lingering: case lingering {
          Some(lingering) -> dict.insert(cast.lingering, id, lingering)
          None -> cast.lingering
        },
        timers: dict.merge(cast.timers, dict.from_list(timers)),
        stealth: dict.merge(cast.stealth, dict.from_list(stealth)),
        procs: dict.merge(cast.procs, dict.from_list(procs)),
        passive: Some(id),
      )
  }
}

/// Whether a timer belongs to the passive's own tree: one of its cast `id`, a modifier
/// or cooldown effect of that cast, or the start of a child whose root is its spell.
fn belongs_to_passive(
  due due: Due,
  id id: Int,
  spell4_id spell4_id: Option(Spell4Id),
) -> Bool {
  case due {
    Go(cast_id:, ..)
    | Finish(cast_id:)
    | NodesEnd(cast_id:)
    | Tick(cast_id:, ..) -> cast_id == id
    ModifierStart(source:, ..)
    | ModifierEnd(source:)
    | RestrictionEnd(source:)
    | ProcDue(source:, ..)
    | CooldownModifierStarts(source:, ..)
    | CooldownModifierEnds(source:) -> source.cast_id == id
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) ->
      on.source.cast_id == id
    StartChild(root:, ..) -> Some(root) == spell4_id
    StateEnd(..) | StartHeld | RepeatHeld | WindowEnd(..) | ChargeLevel(..) ->
      False
  }
}

/// The caster took damage: its health or its shield was lowered by a landed blow
/// (genesis_prime/game/player_life `DamageTaken`). Each cast that holds a stealth source
/// damage breaks loses its node on the caster, as a type 80 removal takes it off, and the
/// input ends with `StealthChanged` when the caster is no longer stealthed. A source kept
/// on damage stays (`Spell4Effects.effectType.83`: dataBits02).
pub fn damage_taken(
  cast cast: State,
  caster caster: Caster,
  now now: Now,
) -> #(State, List(Effect)) {
  use <- settled(cast:, own: [])
  broken_by_damage(cast:, caster:, now_ms: now.monotonic_ms)
}

/// Takes the node off the caster of each cast that holds a source damage breaks
/// (`damage_taken`); nothing when the caster holds none.
fn broken_by_damage(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let sources =
    dict.filter(cast.stealth, fn(_, breaks) {
      breaks == spell_plan.BrokenByDamage
    })
    |> dict.keys
  stealth_ended(cast:, caster:, sources:, now_ms:)
}

/// The casts that hold the stealth sources taken off the caster, oldest cast first, each
/// as a type 80 removal takes a cast off a unit (`node_off`: 0x811, and the 0x7fe of a
/// lingering cast of a method the client keeps), which drops every source of the cast
/// with its node (`effects_ended`).
fn stealth_ended(
  cast cast: State,
  caster caster: Caster,
  sources sources: List(unit_properties.Source),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let removals =
    list.map(sources, fn(source) { source.cast_id })
    |> list.unique
    |> list.sort(int.compare)
    |> list.map(fn(cast_id) {
      lasting.NodeOff(cast_id:, unit_id: caster.unit_id)
    })
  apply_removals(cast:, removals:, now_ms:)
}

/// Each property modifier the caster's casts may still hold, told ended in order: those
/// of the spells of its live and lingering casts, in cast id order, and those whose end
/// a timer waits for, in timer order; each once.
fn modifiers_pending(cast cast: State) -> List(Effect) {
  let held =
    list.flat_map(cast_state.holders(cast:), fn(entry) {
      list.map(caster_rows(spell: { entry.1 }.spell), fn(row) {
        unit_properties.Source(cast_id: entry.0, effect_id: row.effect_id)
      })
    })
  let waiting =
    cast_state.timers_in_order(cast:)
    |> list.filter_map(fn(entry) {
      case entry.1 {
        ModifierEnd(source:) -> Ok(source)
        ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ProcDue(..)
        | RestrictionEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> Error(Nil)
      }
    })
  list.unique(list.append(held, waiting))
  |> list.map(fn(source) { CasterChangeEnds(source:) })
}

/// A cast of the spell starts: its id, the start written to the caster (0x7fd for
/// a press, 0x7ff for a child) and told to the audience, the global cooldown, the
/// threshold's message and timers when the cast opens or moves one, the timer of
/// each later go and of a channel's finish, and the first go at once when it has
/// no wait.
fn start(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  spell spell: Spell,
  root root: Spell4Id,
  parent parent: Option(Spell4Id),
  primary_target primary_target: Int,
  client_cast_id client_cast_id: Option(Int),
  role role: Role,
  spent spent: Option(Int),
  reserved reserved: List(Payment),
) -> #(State, List(Effect)) {
  let id = cast_state.next_cast_id(cast:, caster:)
  let audience = caster.audience
  let go_times = spell_plan.go_times_ms(spell:)
  let gos =
    list.index_map(go_times, fn(wait_ms, phase) {
      #(wait_ms, Go(cast_id: id, phase:))
    })
    |> list.filter(fn(go) { go.0 > 0 })
  let finishing = case spell_plan.finish_after_ms(spell:) {
    Some(wait_ms) -> [#(wait_ms, Finish(cast_id: id))]
    None -> []
  }
  let #(cast, timer_effects) =
    list.fold(list.append(gos, finishing), #(cast, []), fn(so_far, wait) {
      let #(cast, effects) = so_far
      let #(cast, _, start) =
        cast_state.armed(cast:, due: wait.1, after_ms: wait.0)
      #(cast, list.append(effects, [start]))
    })
  let start_message =
    cast_frame.started_message(
      id:,
      spell:,
      root:,
      parent:,
      primary_target:,
      caster:,
      activating: case role {
        Activation(..) -> True
        Child | Base(..) | Stage(..) | Passive | Shortcut(..) -> False
      },
    )
  let live =
    Live(
      spell:,
      spent:,
      reserved:,
      root:,
      parent:,
      primary_target:,
      audience:,
      gone: 0,
      started_ms: now_ms,
      stage_of: case role {
        Stage(ability:, ..) -> Some(ability)
        Child | Base(..) | Passive | Activation(..) | Shortcut(..) -> None
      },
      closes_threshold: closes_threshold(role:),
      nodes: dict.new(),
      ticking: dict.new(),
      activation: case role {
        Activation(activating:, ..) -> Some(activating)
        Child | Base(..) | Stage(..) | Passive | Shortcut(..) -> None
      },
      interaction: case role {
        Activation(interaction:, ..) | Shortcut(interaction:, ..) -> interaction
        Child | Base(..) | Stage(..) | Passive -> NoInteraction
      },
      shortcut: case role {
        Shortcut(..) -> True
        Child | Base(..) | Stage(..) | Passive | Activation(..) -> False
      },
      aimed: case role {
        Shortcut(aimed:, ..) -> aimed
        Child | Base(..) | Stage(..) | Passive | Activation(..) -> None
      },
      finish_due: False,
    )
  let global_ends = case role, spell.global_cooldown.starts_for_ms {
    Passive, _ -> cast.global_cooldown_ends_ms
    Child, Some(wait_ms)
    | Base(..), Some(wait_ms)
    | Stage(..), Some(wait_ms)
    | Activation(..), Some(wait_ms)
    | Shortcut(..), Some(wait_ms)
    -> Some(now_ms + wait_ms)
    Child, None
    | Base(..), None
    | Stage(..), None
    | Activation(..), None
    | Shortcut(..), None
    -> cast.global_cooldown_ends_ms
  }
  let cast =
    State(
      ..cast,
      presses: cast.presses + 1,
      global_cooldown_ends_ms: global_ends,
      casts: dict.insert(cast.casts, id, live),
      pending: case role {
        Base(..) | Stage(..) ->
          list.append(cast.pending, [
            proc.Event(
              trigger: spell_plan.UsesAbility,
              other_unit: None,
              spell: Some(event_spell(spell:)),
            ),
          ])
        Child | Passive | Activation(..) | Shortcut(..) -> cast.pending
      },
      passive: case role {
        Passive -> Some(id)
        Child | Base(..) | Stage(..) | Activation(..) | Shortcut(..) ->
          cast.passive
      },
      current: case
        role != Passive
        && spell_plan.shows_cast_bar(spell:, pressed: root == spell.spell4_id)
      {
        True -> Some(id)
        False -> cast.current
      },
    )
  let to_caster = case client_cast_id {
    Some(client_cast_id) ->
      cast_frame.confirmed_frame(client_cast_id:, start: start_message)
    None -> cast_frame.started_frame(start: start_message)
  }
  let told =
    list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastStarted(start: start_message),
      )
    })
  let #(cast, threshold_effects) = threshold_step(cast:, role:, cast_id: id)
  let #(cast, dropped_effects) = controls_dropped(cast:, spell:)
  let opening =
    list.flatten([
      dropped_effects,
      [Send(frame: to_caster)],
      told,
      threshold_effects,
      timer_effects,
    ])
  case go_times {
    [0, ..] -> {
      let #(cast, going) = asked(cast:, caster:, now_ms:, cast_id: id, phase: 0)
      #(cast, list.append(opening, going))
    }
    _ -> #(cast, opening)
  }
}

/// Whether the finish of a cast that is a stage closes its ability's threshold: a
/// release always does, a tap only when it is the last stage.
fn closes_threshold(role role: Role) -> Bool {
  case role {
    Child | Base(..) | Passive | Activation(..) | Shortcut(..) -> False
    Stage(ability:, index:) ->
      case ability.method {
        spell_plan.ChargeRelease -> True
        spell_plan.RapidTap -> index + 1 >= list.length(ability.stages)
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> False
      }
  }
}

/// The threshold's part of a cast's start: the ability's own spell opens one
/// (0x816, with its time or its charge timer), and a tap that is not the last
/// moves the index of a RapidTap one (0x817).
fn threshold_step(
  cast cast: State,
  role role: Role,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  case role {
    Child | Passive | Activation(..) | Shortcut(..) -> #(cast, [])
    Base(ability:, bag_spell:) ->
      case spell_plan.opens_threshold(spell: ability) {
        True -> open_threshold(cast:, ability:, bag_spell:, cast_id:)
        False -> #(cast, [])
      }
    Stage(ability:, index:) ->
      case dict.get(cast.thresholds, ability.spell4_id.value) {
        Error(Nil) -> #(cast, [])
        Ok(threshold) -> {
          let next = index + 1
          case
            ability.method == spell_plan.RapidTap
            && next < list.length(ability.stages)
          {
            True -> #(
              State(
                ..cast,
                thresholds: dict.insert(
                  cast.thresholds,
                  ability.spell4_id.value,
                  Threshold(..threshold, index: next),
                ),
              ),
              [
                Send(frame: cast_frame.index_frame(
                  spell4_id: ability.spell4_id,
                  index: next,
                )),
              ],
            )
            False -> #(cast, [])
          }
        }
      }
  }
}

/// The ability's first press opens its threshold at index 0: 0x816 with the base
/// cast's id, and the timer of its time (RapidTap) or of its first charge level
/// (ChargeRelease).
fn open_threshold(
  cast cast: State,
  ability ability: Spell,
  bag_spell bag_spell: Spell4Id,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      thresholds: dict.insert(
        cast.thresholds,
        ability.spell4_id.value,
        Threshold(ability:, bag_spell:, index: 0, cast_id:),
      ),
    )
  let opened =
    Send(frame: cast_frame.opened_frame(
      spell4_id: ability.spell4_id,
      bag_spell:,
      cast_id:,
    ))
  case ability.method {
    spell_plan.RapidTap -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: WindowEnd(spell4_id: ability.spell4_id.value),
          after_ms: ability.threshold_ms,
        )
      #(cast, [opened, start])
    }
    spell_plan.ChargeRelease -> {
      let #(cast, waiting) = charge_timer(cast:, ability:, level: 1)
      #(cast, [opened, ..waiting])
    }
    spell_plan.Normal
    | spell_plan.Channeled
    | spell_plan.PressHold
    | spell_plan.ChanneledField
    | spell_plan.ClientSideInteraction
    | spell_plan.Multiphase
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> #(cast, [opened])
  }
}

/// The timer of the charge level `level`, after the row's thresholdDuration, when
/// the ability has that row.
fn charge_timer(
  cast cast: State,
  ability ability: Spell,
  level level: Int,
) -> #(State, List(Effect)) {
  case list.drop(ability.stages, level) |> list.first {
    Error(Nil) -> #(cast, [])
    Ok(stage) -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: ChargeLevel(spell4_id: ability.spell4_id.value, level:),
          after_ms: stage.duration_ms,
        )
      #(cast, [start])
    }
  }
}

/// The charge reaches `level`: 0x817, and the timer of the next level.
fn charge_level_reached(
  cast cast: State,
  spell4_id spell4_id: Int,
  level level: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let cast =
        State(
          ..cast,
          thresholds: dict.insert(
            cast.thresholds,
            spell4_id,
            Threshold(..threshold, index: level),
          ),
        )
      let #(cast, waiting) =
        charge_timer(cast:, ability: threshold.ability, level: level + 1)
      #(cast, [
        Send(frame: cast_frame.index_frame(
          spell4_id: threshold.ability.spell4_id,
          index: level,
        )),
        ..waiting
      ])
    }
  }
}

/// A RapidTap threshold's time ran out: the client closes it by itself, so the
/// server writes nothing, closes its own and starts the ability's cooldown
/// (`opcode.0x816`).
fn window_ended(
  cast cast: State,
  spell4_id spell4_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.thresholds, spell4_id) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> #(
      start_cooldown(
        cast: State(..cast, thresholds: dict.delete(cast.thresholds, spell4_id)),
        spell: threshold.ability,
        now_ms:,
      ),
      [],
    )
  }
}

/// The ability's threshold closes: its timers are cancelled and 0x814 is sent. A
/// RapidTap one starts the ability's cooldown with the bit; a ChargeRelease one
/// ends its base cast with 0x7fe after the 0x814.
fn close_threshold(
  cast cast: State,
  ability ability: Spell,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let key = ability.spell4_id.value
  case dict.get(cast.thresholds, key) {
    Error(Nil) -> #(cast, [])
    Ok(threshold) -> {
      let #(cast, cancels) =
        cast_state.cancel_timers(cast:, matching: fn(due) {
          case due {
            WindowEnd(spell4_id:) | ChargeLevel(spell4_id:, ..) ->
              spell4_id == key
            Go(..)
            | Finish(..)
            | StartChild(..)
            | NodesEnd(..)
            | StateEnd(..)
            | ModifierStart(..)
            | TargetModifierStart(..)
            | ForcedMoveStart(..)
            | ModifierEnd(..)
            | RestrictionEnd(..)
            | CooldownModifierStarts(..)
            | CooldownModifierEnds(..)
            | ProcDue(..)
            | StartHeld
            | RepeatHeld
            | Tick(..) -> False
          }
        })
      let cast = State(..cast, thresholds: dict.delete(cast.thresholds, key))
      case ability.method {
        spell_plan.RapidTap -> #(
          start_cooldown(cast:, spell: ability, now_ms:),
          list.append(cancels, [
            Send(frame: cast_frame.closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 1,
            )),
          ]),
        )
        spell_plan.ChargeRelease -> {
          let closed =
            Send(frame: cast_frame.closed_frame(
              spell4_id: ability.spell4_id,
              start_cooldowns: 0,
            ))
          let #(cast, ended) =
            end_base_cast(cast:, cast_id: threshold.cast_id, now_ms:)
          #(cast, list.flatten([cancels, [closed], ended]))
        }
        spell_plan.Normal
        | spell_plan.Channeled
        | spell_plan.PressHold
        | spell_plan.ChanneledField
        | spell_plan.ClientSideInteraction
        | spell_plan.Multiphase
        | spell_plan.Transactional
        | spell_plan.OtherMethod(..) -> #(cast, cancels)
      }
    }
  }
}

/// The base cast of a charge ends with its 0x7fe, when it is still live.
fn end_base_cast(
  cast cast: State,
  cast_id cast_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Ok(base) -> finish(cast:, cast_id:, live: base, now_ms:)
    Error(Nil) -> #(cast, [])
  }
}

/// The spell's own cooldown starts now, unless it is running already or the spell
/// has none. Its group cooldowns do not start: the server keeps none, so it is never
/// stricter than the client.
fn start_cooldown(
  cast cast: State,
  spell spell: Spell,
  now_ms now_ms: Int,
) -> State {
  State(
    ..cast,
    cooldowns: cooldown.start(
      book: cast.cooldowns,
      keys: cooldown.keys(
        spell4_id: spell.spell4_id,
        spell4_base_id: spell.spell4_base_id,
        spell_groups: spell.groups,
        cooldown_groups: spell.cooldown_groups,
      ),
      cooldown_ms: spell.cooldown_ms,
      now_ms:,
    ),
  )
}

/// The go of phase `phase` of a live cast, with the units its round struck: 0x7f4 to
/// the caster and the audience, then the 0x7fb of the deflected ones (the client
/// accepts either order and drops a miss after the finish, `cast.miss_order`), the
/// spell's own cooldown at the go its method names, the current cast cleared as the
/// client does, the Proxies of the phase whose gates pass, and the finish after the
/// last go. A cast that is not live has no go.
fn go(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  cast_id cast_id: Int,
  phase phase: Int,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id) {
    Error(Nil) -> #(cast, [])
    Ok(live) -> {
      let spell = live.spell
      let go_count = spell_plan.go_count(spell:)
      let cast = case spell.cooldown_start {
        spell_plan.AtFirstGo if live.gone == 0 ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtLastGo if live.gone + 1 == go_count ->
          start_cooldown(cast:, spell:, now_ms:)
        spell_plan.AtFirstGo | spell_plan.AtLastGo | spell_plan.NotAtAGo -> cast
      }
      let cast = case live.stage_of {
        Some(ability)
          if spell.method == spell_plan.ChargeRelease && live.gone == 0
        -> start_cooldown(cast:, spell: ability, now_ms:)
        Some(_) | None -> cast
      }
      let current = case cast_gate.clears_current(cast:, live:, cast_id:) {
        True -> None
        False -> cast.current
      }
      let live = Live(..live, gone: live.gone + 1)
      let cast =
        State(..cast, current:, casts: dict.insert(cast.casts, cast_id, live))
      // The subject is read once here, before the children start and before the
      // finish: every gate of this go decides on the state before the go's own effects.
      let subject = subject_of(cast:, caster:)
      let #(starting, gate_logs, rolls) =
        cast_gate.proxy_gates(
          proxies: cast_gate.proxies_with_targets(
            spell:,
            phase:,
            struck:,
            spent: live.spent,
          ),
          subject:,
          rolls:,
        )
      let #(gains, rolls) =
        cast_gate.gains_given(
          spell:,
          phase:,
          starting:,
          subject:,
          rolls:,
          spent: live.spent,
        )
      let #(applied, lasting_logs, rolls) =
        lasting_applied(spell:, phase:, spent: live.spent, subject:, rolls:)
      let #(cast, restricting) =
        restrictions_numbered(cast:, caster:, cast_id:, live:, applied:)
      let aimed =
        aimed_at(
          applied:,
          caster:,
          live:,
          struck:,
          gates_passed:,
          phase:,
          restricting:,
          target_verdict: target_verdict_on(
            cast:,
            caster:,
            subject:,
            poses:,
            indexes:,
            units:,
          ),
          rolls:,
        )
      let go_message =
        cast_frame.go_message(
          cast_id:,
          phase:,
          place: caster.place,
          struck:,
          listed: aimed.units,
        )
      let missed = cast_frame.missed_message(cast_id:, struck:)
      let going =
        list.flatten([
          [Send(frame: cast_frame.went_frame(go: go_message))],
          list.map(map.sorted_connections(live.audience), fn(viewer) {
            Tell(to: viewer, news: client_connection.CastWent(go: go_message))
          }),
          case missed {
            Some(missed) -> [
              Send(frame: cast_frame.missed_frame(missed:)),
              ..list.map(map.sorted_connections(live.audience), fn(viewer) {
                Tell(to: viewer, news: client_connection.CastMissed(missed:))
              })
            ]
            None -> []
          },
        ])
      let immune =
        list.filter_map(struck, fn(one) {
          case one {
            Immune(unit_id:, ..) ->
              Ok(
                Send(frame: cast_frame.immunity_logged_frame(
                  caster_unit_id: caster.unit_id,
                  unit_id:,
                  spell4_id: spell.spell4_id,
                )),
              )
            Hit(..) | Deflected(..) -> Error(Nil)
          }
        })
      let armor_logged =
        list.filter_map(struck, fn(one) {
          case one {
            Hit(unit_id:, armor_removed:, ..)
              | Immune(unit_id:, armor_removed:, ..)
              if armor_removed > 0
            ->
              Ok(
                Send(frame: cast_frame.armor_logged_frame(
                  caster_unit_id: caster.unit_id,
                  unit_id:,
                  spell4_id: spell.spell4_id,
                  amount: armor_removed,
                )),
              )
            Hit(..) | Immune(..) | Deflected(..) -> Error(Nil)
          }
        })
      let shown = restrictions_shown(restricting:, caster:, live:)
      let #(cast, removed) = removed_by_go(cast:, aimed:, now_ms:)
      let #(cast, logged) =
        cast_frame.states_logged(
          cast:,
          caster:,
          spell4_id: spell.spell4_id,
          aimed:,
          now_ms:,
        )
      let #(cast, given) = nodes_given(cast:, cast_id:, aimed:, now_ms:)
      let #(cast, ticks) =
        ticks_armed(
          cast:,
          cast_id:,
          go: live.gone,
          from_ms: now_ms,
          rows: aimed.ticking,
        )
      let #(cast, never_held) = procs_held(cast:, cast_id:, applied:)
      let #(cast, modifying) =
        modifiers_armed(cast:, cast_id:, caster:, aimed:, struck:)
      let #(cast, throwing) =
        struck_moves_armed(cast:, cast_id:, thrown: aimed.thrown, struck:)
      let #(cast, healing) = heals_armed(cast:, cast_id:, aimed:)
      let #(cast, restriction_timers) =
        restrictions_armed(cast:, cast_id:, restricting:)
      let #(cast, cooldowns) =
        cooldowns_armed(
          cast:,
          cast_id:,
          aimed:,
          longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
          now_ms:,
        )
      let #(cast, children, _) =
        list.fold(starting, #(cast, [], aimed.rolls_left), fn(so_far, proxy) {
          let #(cast, effects, rolls) = so_far
          let #(cast, more, rolls) =
            children(
              cast:,
              caster:,
              now_ms:,
              live:,
              proxy:,
              struck:,
              subject:,
              poses:,
              indexes:,
              units:,
              rolls:,
            )
          #(cast, list.append(effects, more), rolls)
        })
      let #(cast, stealth) =
        stealth_changed_by_go(
          cast:,
          caster:,
          cast_id:,
          spell:,
          applied:,
          last_go: live.gone >= go_count,
          now_ms:,
        )
      let #(cast, finished) = case
        live.gone == go_count
        && {
          live.finish_due || option.is_none(spell_plan.finish_after_ms(spell:))
        }
      {
        True ->
          case dict.get(cast.casts, cast_id) {
            Ok(live) -> finish_or_linger(cast:, cast_id:, live:, now_ms:)
            Error(Nil) -> #(cast, [])
          }
        False -> #(cast, [])
      }
      // A cast that goes on after this go has its `NodesEnd` timer started for the
      // earliest end of its nodes; one that ended or lingers did that in its end.
      let #(cast, armed) = case
        nodes_aimed(aimed:) != [] && dict.has_key(cast.casts, cast_id)
      {
        True -> rearmed(cast:, cast_id:, now_ms:)
        False -> #(cast, [])
      }
      // The activation is applied by the cast's last go: a channel's Activate row is
      // delayed to it (Spell4Effects 10256, delayTime 2999 of a 3000 ms channel), though
      // the first go lists the row (phaseFlags 1). A cast stopped before its last go
      // activates nothing: the server's choice, since the client's own handling of the
      // Activate effect (`Spell4Effects.effectType.7`) is not read here for a stopped
      // channel.
      let activated = case live.activation {
        Some(Activating(unit_id:, creature_id:, alive_at_press:, by_item:, ..))
          if live.gone == go_count
        -> [Activated(unit_id:, creature_id:, alive_at_press:, by_item:)]
        Some(_) | None -> []
      }
      // The first go of a quest button's cast counts the objective: a later go of the
      // same cast counts nothing more.
      let counted = case live.shortcut && live.gone == 1 {
        True -> [
          ShortcutCast(spell4_id: spell.spell4_id.value, target: live.aimed),
        ]
        False -> []
      }
      #(
        cast,
        list.flatten([
          going,
          immune,
          armor_logged,
          shown,
          logged,
          removed,
          given,
          ticks,
          never_held,
          modifying,
          throwing,
          healing,
          restriction_timers,
          cooldowns,
          gains,
          gate_logs,
          lasting_logs,
          aimed.reach_logs,
          children,
          stealth,
          finished,
          activated,
          counted,
          armed,
        ]),
      )
    }
  }
}

/// What a go does to the caster's stealth, after the go's other effects: each Stealth row
/// that applied adds its source (the cast `cast_id`, the row's effect) with the row's
/// `Breaks`; a RemoveStealth row that applied ends every source; then a spell whose
/// `stealth_change` ends stealth at this go (`EndsStealthAtEachGo`, or
/// `EndsStealthAfterLastGo` when `last_go`) ends the sources of the other casts. A cast
/// never ends the sources of its own Stealth rows, whichever go applied them. A source
/// ends as `cast.stealth` loses it and its cast's node leaves the caster, as `node_off`
/// takes a type 80 removal's (0x811, and the 0x7fe of a lingering cast of a method the
/// client keeps). A go with no row, and no source to end, changes nothing.
///
/// A cast of `EndsStealthAfterLastGo` that stops before its last go does not reach this
/// for the goes it missed; `end_live_cast` ends the stealth when it stops after a go.
fn stealth_changed_by_go(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  spell spell: Spell,
  applied applied: Applied,
  last_go last_go: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.stealthed(cast:), applied.stealth, applied.remove_stealth {
    False, [], [] -> #(cast, [])
    _, _, _ -> {
      let cast =
        State(
          ..cast,
          stealth: list.fold(applied.stealth, cast.stealth, fn(held, row) {
            dict.insert(
              held,
              unit_properties.Source(cast_id:, effect_id: row.effect_id),
              row.breaks,
            )
          }),
        )
      let #(cast, removed) = case applied.remove_stealth {
        [] -> #(cast, [])
        [_, ..] ->
          stealth_ended(
            cast:,
            caster:,
            sources: dict.keys(cast.stealth),
            now_ms:,
          )
      }
      let #(cast, broken) = case spell.stealth_change, last_go {
        spell_plan.EndsStealthAtEachGo, _
        | spell_plan.EndsStealthAfterLastGo, True
        ->
          stealth_ended(
            cast:,
            caster:,
            sources: other_casts_sources(cast:, cast_id:),
            now_ms:,
          )
        spell_plan.EndsStealthAfterLastGo, False | spell_plan.KeepsStealth, _ -> #(
          cast,
          [],
        )
      }
      #(cast, list.append(removed, broken))
    }
  }
}

/// The Fluff, SpellForceRemove, property modifier, forced move, cooldown, Stealth,
/// RemoveStealth and HealShields effects of the phase whose gates pass against the caster,
/// a debug line for each that cannot be decided, and the rolls left. Their gates are checked after the Proxies' and the gains', in that
/// order, the HealShields effects' last (`rolls_needed`).
fn lasting_applied(
  spell spell: Spell,
  phase phase: Int,
  spent spent: Option(Int),
  subject subject: prerequisite.Subject,
  rolls rolls: List(Int),
) -> #(Applied, List(Effect), List(Int)) {
  let #(lasting, logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.lasting_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.Lasting) {
        cast_gate.caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.Lasting) {
        "the lasting effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(removes, more_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.removes_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.ForceRemove) {
        cast_gate.caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.ForceRemove) {
        "the SpellForceRemove effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(modifiers, modifier_logs, rolls) =
    cast_gate.gated(
      rows: list.filter(
        spell_plan.modifiers_in_phase(spell:, phase:, spent:),
        modifier_has_life,
      ),
      gates: fn(row: spell_plan.PropertyModifier) {
        cast_gate.caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.PropertyModifier) {
        "the "
        <> modifier_kind_named(row:)
        <> " effect "
        <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(forced_moves, forced_move_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.forced_moves_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.ForcedMove) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.ForcedMove) {
        "the ForcedMove effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(struck_moves, struck_move_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.struck_moves_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.StruckMove) {
        cast_gate.caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.StruckMove) {
        "the ForcedMove effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(cooldowns, cooldown_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.cooldown_modifiers_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.CooldownModifier) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.CooldownModifier) {
        "the ModifySpellCooldown effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(stealth, stealth_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.stealth_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.StealthRow) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.StealthRow) {
        "the Stealth effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(remove_stealth, remove_stealth_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.remove_stealth_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.RemoveStealthRow) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.RemoveStealthRow) {
        "the RemoveStealth effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(procs, proc_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.procs_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.ProcRow) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.ProcRow) {
        "the Proc effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(heals, heal_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.heals_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.Heal) {
        cast_gate.caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.Heal) {
        "the Heal or HealShields effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  let #(restrictions, restriction_logs, rolls) =
    cast_gate.gated(
      rows: spell_plan.restrictions_in_phase(spell:, phase:, spent:),
      gates: fn(row: spell_plan.CrowdControl) {
        cast_gate.only_on_caster_gates(condition: row.condition)
      },
      what: fn(row: spell_plan.CrowdControl) {
        "the ability restriction effect " <> int.to_string(row.effect_id.value)
      },
      outcome: "so it is not applied",
      subject:,
      rolls:,
    )
  #(
    Applied(
      lasting:,
      removes:,
      modifiers:,
      forced_moves:,
      struck_moves:,
      cooldowns:,
      stealth:,
      remove_stealth:,
      procs:,
      heals:,
      restrictions:,
    ),
    list.flatten([
      logs,
      more_logs,
      modifier_logs,
      forced_move_logs,
      struck_move_logs,
      cooldown_logs,
      stealth_logs,
      remove_stealth_logs,
      proc_logs,
      heal_logs,
      restriction_logs,
    ]),
    rolls,
  )
}

/// The go's states on the caster, each with its instance id: the one a cast already holds
/// for the effect, or the next of the caster's counter, held with the go's audience.
fn restrictions_numbered(
  cast cast: State,
  caster caster: Caster,
  cast_id cast_id: Int,
  live live: Live,
  applied applied: Applied,
) -> #(State, List(Restricting)) {
  list.fold(applied.restrictions, #(cast, []), fn(so_far, row) {
    let #(cast, numbered) = so_far
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, restricting) = case dict.get(cast.restrictions, source) {
      Ok(held) -> #(
        cast,
        Restricting(row:, instance_id: held.instance_id, fresh: False),
      )
      Error(Nil) -> {
        let told = cast.restrictions_told + 1
        let instance_id =
          crowd_control.instance_id(caster_unit_id: caster.unit_id, count: told)
        #(
          State(
            ..cast,
            restrictions: dict.insert(
              cast.restrictions,
              source,
              HeldRestriction(
                state: row.row.state,
                instance_id:,
                audience: live.audience,
              ),
            ),
            restrictions_told: told,
          ),
          Restricting(row:, instance_id:, fresh: True),
        )
      }
    }
    #(cast, list.append(numbered, [restricting]))
  })
}

/// 0x87f to the caster and to the audience of the go, for each state the go gave
/// (`opcode.0x87f`); a state a cast already held is not told again. A Tether on the
/// caster is told its anchor first, the caster's own unit, by a 0x881 to the caster
/// alone: the message sets the anchor of the unit the receiving client controls and
/// names no unit, so the audience, whose clients control other units, gets none
/// (`opcode.0x881`). That the anchor is the caster's own unit is a guess; no client
/// value names it, and the issue "Spells work in depth on the real client: cast times, telegraphs, buffs,
/// crowd control and ticking effects" will settle it.
fn restrictions_shown(
  restricting restricting: List(Restricting),
  caster caster: Caster,
  live live: Live,
) -> List(Effect) {
  restricting
  |> list.filter(fn(one) { one.fresh })
  |> list.flat_map(fn(one) {
    let state = one.row.row.state
    list.flatten([
      case state == crowd_control_state.Tether {
        True -> [
          Send(frame: cast_frame.tether_anchor_frame(
            anchor_unit_id: caster.unit_id,
          )),
        ]
        False -> []
      },
      [
        Send(frame: cast_frame.control_applied_frame(
          unit_id: caster.unit_id,
          state:,
          instance_id: one.instance_id,
        )),
        ..list.map(map.sorted_connections(live.audience), fn(viewer) {
          Tell(
            to: viewer,
            news: client_connection.CrowdControlApplied(
              state:,
              instance_id: one.instance_id,
            ),
          )
        })
      ],
    ])
  })
}

/// The end of each state a go holds on the caster, on a timer of its delay and duration
/// unless it lasts until removed: the client's lifetime for a CCStateSet effect is
/// `trunc(durationTime * m + 0.5)` after its delay (`0x1405d6880`, `0x1405d8770`) and the
/// client never ends the state itself, so the server's timer does, as for a state on a
/// creature. A row of duration 0 without flag 2 lives 0 ms and ends in the go's own
/// step. A later go of the cast arms the state's end again from that go; the node's end
/// or removal cancels it (`effects_ended`).
fn restrictions_armed(
  cast cast: State,
  cast_id cast_id: Int,
  restricting restricting: List(Restricting),
) -> #(State, List(Effect)) {
  list.fold(restricting, #(cast, []), fn(so_far, one) {
    let #(cast, effects) = so_far
    let source = unit_properties.Source(cast_id:, effect_id: one.row.effect_id)
    let row = one.row.row
    let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
    case row.until_removed {
      True -> #(cast, list.append(effects, cancels))
      False -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: RestrictionEnd(source:),
            after_ms: row.delay_ms + row.duration_ms,
          )
        #(cast, list.flatten([effects, cancels, [start]]))
      }
    }
  })
}

/// The state the effect `source` gave the caster ends with its row, ahead of its cast's
/// node: 0x880 to the caster and the audience told of it. A state no longer held, because
/// the node ended or was taken off first, or the caster died or left, ends nothing.
fn restriction_ended(
  cast cast: State,
  source source: unit_properties.Source,
) -> #(State, List(Effect)) {
  case dict.get(cast.restrictions, source) {
    Error(Nil) -> #(cast, [])
    Ok(held) -> #(
      State(..cast, restrictions: dict.delete(cast.restrictions, source)),
      restrictions_ended(held: [#(source, held)], cast_id: source.cast_id),
    )
  }
}

/// 0x880 to the caster and to the audience that was told the state, for each state the
/// cast `cast_id` held, in effect id order (`opcode.0x880`).
fn restrictions_ended(
  held held: List(#(unit_properties.Source, HeldRestriction)),
  cast_id cast_id: Int,
) -> List(Effect) {
  held
  |> list.sort(fn(first, second) {
    int.compare({ first.0 }.effect_id.value, { second.0 }.effect_id.value)
  })
  |> list.flat_map(fn(entry) {
    let restriction = entry.1
    [
      Send(frame: cast_frame.control_ended_frame(
        unit_id: cast_state.caster_of(cast_id:),
        state: restriction.state,
        cast_id:,
        instance_id: restriction.instance_id,
      )),
      ..list.map(map.sorted_connections(restriction.audience), fn(viewer) {
        Tell(
          to: viewer,
          news: client_connection.CrowdControlEnded(
            state: restriction.state,
            cast_id:,
            instance_id: restriction.instance_id,
          ),
        )
      })
    ]
  })
}

/// Whether a go of phase `phase` lists the activation's Activate effect. A channel lists
/// it only at the go its phaseFlags name: Spell4Effects 10256 has phaseFlags 1, the first
/// go (`cast.channel_sequence`). A spell cast as a Normal one goes once, so it lists every
/// row, whatever phase the row names (an activate cast drops the phases,
/// `activation_spell`).
fn activation_listed_at(
  live live: Live,
  phase phase: Int,
) -> fn(activate.ActivateEffect) -> Bool {
  fn(effect: activate.ActivateEffect) {
    live.spell.method != spell_plan.Channeled
    || spell_plan.has_flag(
      flags: effect.phase_flags,
      bit: spell_plan.phase_bit(phase:),
    )
  }
}

/// The check of a target apply prerequisite for the unit it would reach. The first unit
/// is the unit the effect reaches and the second the caster
/// (`Spell4Effects.prerequisiteIdTargetApply`): the caster's whole unit as `subject` has
/// it for the caster, and another unit as the caster's picture shows it (`struck_subject`).
fn target_verdict_on(
  cast cast: State,
  caster caster: Caster,
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> TargetVerdict {
  fn(gate, unit_id, rolls) {
    let on_unit = case unit_id == caster.unit_id {
      True -> subject
      False ->
        struck_subject(
          cast:,
          caster:,
          primary_target: unit_id,
          poses:,
          indexes:,
          units:,
        )
    }
    cast_gate.checked(prerequisite: gate, subject: on_unit, rolls:)
  }
}

/// The gate a go's strike checks its damage, periodic damage and crowd-control rows by,
/// in the caster's picture: the caster side against the caster's unit as both units
/// (`gates_gate`), the target side for a unit by its first unit and the caster second
/// (`unit_gate`), so a row behind no target gate starts for every unit. A row the server
/// cannot tell is not applied and a debug line says so.
pub fn strike_gate(
  cast cast: State,
  caster caster: Caster,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> StrikeGate {
  let subject = subject_of(cast:, caster:)
  let target_verdict =
    target_verdict_on(cast:, caster:, subject:, poses:, indexes:, units:)
  fn(condition, side, what, rolls) {
    case side {
      CasterSide ->
        cast_gate.gates_gate(
          gates: cast_gate.caster_gates(condition:),
          subject:,
          rolls:,
          what:,
          outcome: "so it is not applied",
        )
      UnitSide(unit_id:) ->
        case cast_gate.target_gate_of(condition:) {
          None -> #(Starts, rolls)
          Some(target) ->
            cast_gate.unit_gate(
              target:,
              unit_id:,
              target_verdict:,
              what:,
              outcome: "so it is not applied",
              rolls:,
            )
        }
    }
  }
}

fn aimed_at(
  applied applied: Applied,
  caster caster: Caster,
  live live: Live,
  struck struck: List(Struck),
  gates_passed gates_passed: Dict(Int, List(Int)),
  phase phase: Int,
  restricting restricting: List(Restricting),
  target_verdict target_verdict: TargetVerdict,
  rolls rolls: List(Int),
) -> Aimed {
  let #(lasting, lasting_logs, rolls) =
    cast_gate.rows_with_units(
      rows: applied.lasting,
      aim: fn(row) { row.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> cast_gate.passing_struck_gates(
      effect_id: fn(row: spell_plan.Lasting) { row.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(row: spell_plan.Lasting) { row.condition },
      what: fn(row: spell_plan.Lasting) {
        "the lasting effect " <> int.to_string(row.effect_id.value)
      },
      target_verdict:,
      rolls:,
    )
  let #(removes, remove_logs, rolls) =
    cast_gate.rows_with_units(
      rows: applied.removes,
      aim: fn(row) { row.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> cast_gate.passing_struck_gates(
      effect_id: fn(row: spell_plan.ForceRemove) { row.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(row: spell_plan.ForceRemove) { row.condition },
      what: fn(row: spell_plan.ForceRemove) {
        "the SpellForceRemove effect " <> int.to_string(row.effect_id.value)
      },
      target_verdict:,
      rolls:,
    )
  let controls = controls_landed(struck:)
  let #(modifiers, modifier_logs, rolls) =
    cast_gate.rows_with_units(
      rows: applied.modifiers,
      aim: fn(row) { spell_plan.modifier_aim(modifier: row) },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> list.filter(fn(entry) {
      cast_gate.modifier_applies(
        row: entry.0,
        unit_id: entry.1,
        caster:,
        struck:,
      )
    })
    |> cast_gate.passing_struck_gates(
      effect_id: fn(row: spell_plan.PropertyModifier) { row.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(row: spell_plan.PropertyModifier) { row.condition },
      what: fn(row: spell_plan.PropertyModifier) {
        "the "
        <> modifier_kind_named(row:)
        <> " effect "
        <> int.to_string(row.effect_id.value)
      },
      target_verdict:,
      rolls:,
    )
  let forced_moves = applied.forced_moves
  let #(thrown, thrown_logs, rolls) =
    cast_gate.rows_with_units(
      rows: applied.struck_moves,
      aim: fn(row: spell_plan.StruckMove) { row.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> list.filter(fn(entry) {
      result.is_ok(cast_gate.creature_hit(struck:, unit_id: entry.1))
    })
    |> cast_gate.passing_struck_gates(
      effect_id: fn(row: spell_plan.StruckMove) { row.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(row: spell_plan.StruckMove) { row.condition },
      what: fn(row: spell_plan.StruckMove) {
        "the ForcedMove effect " <> int.to_string(row.effect_id.value)
      },
      target_verdict:,
      rolls:,
    )
  let cooldowns =
    list.map(applied.cooldowns, fn(row) {
      #(
        row,
        caster.unit_id,
        cooldown_kept(
          row:,
          longer_of_delay_and_duration: live.spell.longer_of_delay_and_duration,
        ),
      )
    })
  let stealth = list.map(applied.stealth, fn(row) { #(row, caster.unit_id) })
  let procs = list.map(applied.procs, fn(row) { #(row, caster.unit_id) })
  let #(reached_heals, heal_reach_logs, rolls) =
    cast_gate.rows_with_units(
      rows: applied.heals,
      aim: fn(heal: spell_plan.Heal) { heal.aim },
      caster:,
      primary_target: live.primary_target,
      struck:,
    )
    |> cast_gate.passing_struck_gates(
      effect_id: fn(heal: spell_plan.Heal) { heal.effect_id },
      spell: live.spell,
      caster_unit_id: caster.unit_id,
      gates_passed:,
    )
    |> cast_gate.reaching(
      condition: fn(heal: spell_plan.Heal) { heal.condition },
      what: fn(heal: spell_plan.Heal) {
        "the Heal or HealShields effect " <> int.to_string(heal.effect_id.value)
      },
      target_verdict:,
      rolls:,
    )
  let #(heals, heal_logs) = cast_heal.healed_by(entries: reached_heals, caster:)
  let restrictions = list.map(restricting, fn(one) { #(one, caster.unit_id) })
  let ticking =
    list.append(
      cast_heal.ticking_struck(struck: cast_gate.struck_gates_applied(
        struck:,
        spell: live.spell,
        gates_passed:,
      )),
      cast_heal.ticking_heals(entries: reached_heals, caster:),
    )
  let listed =
    list.flatten([
      list.map(stealth, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(procs, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(lasting, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(modifiers, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(forced_moves, fn(row) {
        #(
          caster.unit_id,
          Listed(
            effect_id: row.effect_id,
            delay_ms: row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(thrown, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(cooldowns, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.row.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(removes, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: 0,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(heals, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.effect_id,
            delay_ms: entry.0.delay_ms,
            instance_id: None,
            damage: Some(cast_heal.heal_description(healed: entry.0)),
          ),
        )
      }),
      list.map(ticking, fn(row) {
        #(
          row.unit_id,
          Listed(
            effect_id: row.effect_id,
            delay_ms: row.schedule.delay_ms,
            instance_id: None,
            damage: None,
          ),
        )
      }),
      list.map(controls, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: Spell4EffectsId(entry.0.tell.effect_id),
            delay_ms: entry.0.tell.row.delay_ms,
            instance_id: Some(entry.0.tell.instance_id),
            damage: None,
          ),
        )
      }),
      list.map(restrictions, fn(entry) {
        #(
          entry.1,
          Listed(
            effect_id: entry.0.row.effect_id,
            delay_ms: entry.0.row.row.delay_ms,
            instance_id: Some(entry.0.instance_id),
            damage: None,
          ),
        )
      }),
      case live.activation {
        Some(Activating(unit_id:, effects:, ..)) ->
          effects
          |> list.filter(activation_listed_at(live:, phase:))
          |> list.map(fn(effect) {
            #(
              unit_id,
              Listed(
                effect_id: effect.effect_id,
                delay_ms: effect.delay_ms,
                instance_id: None,
                damage: None,
              ),
            )
          })
        None -> []
      },
    ])
  let units =
    list.fold(listed, [], fn(units: List(#(Int, List(Listed))), entry) {
      case list.key_find(units, entry.0) {
        Ok(on_unit) ->
          list.key_set(units, entry.0, list.append(on_unit, [entry.1]))
        Error(Nil) -> list.append(units, [#(entry.0, [entry.1])])
      }
    })
  Aimed(
    units:,
    lasting:,
    removes:,
    modifiers:,
    cooldowns:,
    stealth:,
    heals:,
    reach_logs: list.flatten([
      lasting_logs,
      remove_logs,
      modifier_logs,
      thrown_logs,
      heal_reach_logs,
      heal_logs,
    ]),
    thrown:,
    procs:,
    controls:,
    restrictions:,
    ticking:,
    rolls_left: rolls,
  )
}

/// What the row's effect type is called in a log line.
fn modifier_kind_named(row row: spell_plan.PropertyModifier) -> String {
  case row.armor, row.change {
    Some(..), _ -> "ModifyInterruptArmor"
    None, spell_plan.AbsorbChange(..) -> "Absorption"
    None, spell_plan.LookChange(..) -> "DisguiseOutfit"
    None, spell_plan.PropertyChange(..) | None, spell_plan.StruckChange(..) ->
      "UnitPropertyModifier or UnitPropertyConversion"
  }
}

/// Whether a modifier row has a time to be changed for: a durationTime, or flags bit 2.
/// A row with neither changes nothing and gives its node no life.
fn modifier_has_life(row: spell_plan.PropertyModifier) -> Bool {
  lasting.has_life(row: row.row)
}

/// Whether a cooldown row is kept for the cooldowns that start after it takes effect:
/// its lifetime (delay plus durationTime, the larger of the two for a spell with the
/// record flag 0x10000000) ends after its start, or never ends (flags bit 2). Any other
/// row acts once at its start (`0x14046b7f0`, `opcode.0x7f4.effect_time`). Every row
/// aimed at the caster gives its node the lifetime, kept or not.
fn cooldown_kept(
  row row: spell_plan.CooldownModifier,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
) -> Bool {
  row.row.until_removed
  || lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
  > row.row.delay_ms
}

/// The crowd-control states the units of a go took, each with its unit, in the order
/// of the units.
fn controls_landed(
  struck struck: List(Struck),
) -> List(#(strike_tell.ControlLanded, Int)) {
  list.flat_map(struck, fn(one) {
    case one {
      Hit(unit_id:, controls:, ..) | Immune(unit_id:, controls:, ..) ->
        list.map(controls, fn(control) { #(control, unit_id) })
      Deflected(..) -> []
    }
  })
}

/// The type 80 effects of a go taken off the units they aim at, in order: each takes
/// the matching casts of the caster off the unit, oldest first, and writes 0x811 or
/// 0x813 for each (`opcode.0x811`, `opcode.0x813`).
fn removed_by_go(
  cast cast: State,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.removes, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(row, unit_id) = entry
    let removals =
      lasting.removals(
        holds: holds_on(cast:, unit_id:),
        selector: row.selector,
        count: row.count,
        unit_id:,
      )
    let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
    #(cast, list.append(effects, more))
  })
}

/// The property modifiers a go applies, each armed from this go: the modifier of an
/// earlier go of the cast is armed again, its timers cancelled and started anew; a row
/// with no delay starts in this step, any other on a timer of its delay, and one that
/// does not last until removed ends on a timer after its delay and duration.
fn modifiers_armed(
  cast cast: State,
  cast_id cast_id: Int,
  caster caster: Caster,
  aimed aimed: Aimed,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  list.fold(aimed.modifiers, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let row = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, more) = case row.change {
      spell_plan.StruckChange(modifier:, ..) ->
        creature_modifier_armed(
          cast:,
          cast_id:,
          row:,
          modifier:,
          unit_id: entry.1,
          struck:,
        )
      spell_plan.PropertyChange(modifier:) ->
        caster_modifier_armed(cast:, row:, source:, change: Property(modifier:))
      spell_plan.LookChange(disguise:) ->
        caster_modifier_armed(cast:, row:, source:, change: Look(disguise:))
      spell_plan.AbsorbChange(absorption:) ->
        // An absorb's pool is worked out at the go from the caster as it stood before
        // the go's own effects, as a shield heal's amount is (`healed_by`).
        caster_modifier_armed(
          cast:,
          row:,
          source:,
          change: Absorb(
            amount: damage.amount_on_caster(
              formula: absorption.formula,
              caster: cast_heal.on_caster_of(caster:),
            ),
            mask: absorption.mask,
          ),
        )
    }
    #(cast, list.append(effects, more))
  })
}

/// A property modifier on a creature the go struck, armed from this go: the modifier
/// of an earlier go on the same creature is armed again; a row with no delay starts in
/// this step and any other on a timer of its delay. It has no timer of its end: it ends
/// with the cast's node on the creature (`creature_modifiers_ended`).
fn creature_modifier_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.PropertyModifier,
  modifier modifier: unit_properties.Modifier,
  unit_id unit_id: Int,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  case cast_gate.creature_hit(struck:, unit_id:) {
    Error(Nil) -> #(cast, [])
    Ok(#(life, struck_at_ms)) -> {
      let on =
        OnCreature(
          unit_id:,
          life:,
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
        )
      let #(cast, cancels) = target_start_cancelled(cast:, on:)
      case row.row.delay_ms > 0 {
        True -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: TargetModifierStart(on:, modifier:, struck_at_ms:),
              after_ms: row.row.delay_ms,
            )
          #(cast, list.append(cancels, [start]))
        }
        False -> {
          let #(cast, starting) =
            target_modifier_started(cast:, on:, modifier:, struck_at_ms:)
          #(cast, list.append(cancels, starting))
        }
      }
    }
  }
}

/// The creatures a go throws: each entry of `thrown` (a struck move of the phase whose
/// caster gates passed with a creature its aim names that the round `Hit` and that passes
/// its target gate, `aimed_at`), in the row then the unit order of `units_aimed_at`. A row with no delay tells the creature
/// `ForcedMoveStarts` in this step; any other arms a `ForcedMoveStart` timer for the go
/// plus its delay; each go's throw is its own, so a later go of the cast leaves an
/// earlier go's waiting throw to start. A unit that is not a `HitCreature` of the
/// round is not thrown (a deflected one included, as for a property modifier), and neither
/// is the caster or another player (a move of another player is issue 570).
fn struck_moves_armed(
  cast cast: State,
  cast_id cast_id: Int,
  thrown thrown: List(#(spell_plan.StruckMove, Int)),
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  list.fold(thrown, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let #(row, unit_id) = entry
    let #(cast, more) =
      struck_move_armed(cast:, cast_id:, row:, unit_id:, struck:)
    #(cast, list.append(effects, more))
  })
}

/// The throw of one row on one unit its aim names: nothing unless the round `Hit` the
/// unit as a creature, then the start its delay makes.
fn struck_move_armed(
  cast cast: State,
  cast_id cast_id: Int,
  row row: spell_plan.StruckMove,
  unit_id unit_id: Int,
  struck struck: List(Struck),
) -> #(State, List(Effect)) {
  case cast_gate.creature_hit(struck:, unit_id:) {
    Error(Nil) -> #(cast, [])
    Ok(#(life, struck_at_ms)) -> {
      let on =
        OnCreature(
          unit_id:,
          life:,
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
        )
      case row.delay_ms > 0 {
        True -> {
          let #(cast, _, start) =
            cast_state.armed(
              cast:,
              due: ForcedMoveStart(on:, move: row.move, struck_at_ms:),
              after_ms: row.delay_ms,
            )
          #(cast, [start])
        }
        False -> throw_started(cast:, on:, move: row.move, struck_at_ms:)
      }
    }
  }
}

/// The delay of a throw ran out, or it has none: the cast tells the creature `on` names,
/// of the life the go struck, `ForcedMoveStarts`. A node of the cast that ended first has
/// cancelled the timer, so nothing is asked of the node here.
fn throw_started(
  cast cast: State,
  on on: OnCreature,
  move move: forced_move.Move,
  struck_at_ms struck_at_ms: Int,
) -> #(State, List(Effect)) {
  #(cast, [
    ForcedMoveStarts(unit_id: on.unit_id, life: on.life, struck_at_ms:, move:),
  ])
}

/// The start timer of the modifier `on` names cancelled, whichever go armed it.
fn target_start_cancelled(
  cast cast: State,
  on on: OnCreature,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case target_start_of(due:) {
      Ok(waiting) ->
        waiting.unit_id == on.unit_id && waiting.source == on.source
      Error(Nil) -> False
    }
  })
}

/// The modifier or throw on a creature a timer waits to start, none for any other timer.
fn target_start_of(due due: Due) -> Result(OnCreature, Nil) {
  case due {
    TargetModifierStart(on:, ..) | ForcedMoveStart(on:, ..) -> Ok(on)
    Go(..)
    | Finish(..)
    | StartChild(..)
    | NodesEnd(..)
    | StateEnd(..)
    | ModifierStart(..)
    | ModifierEnd(..)
    | RestrictionEnd(..)
    | CooldownModifierStarts(..)
    | CooldownModifierEnds(..)
    | ProcDue(..)
    | StartHeld
    | RepeatHeld
    | WindowEnd(..)
    | ChargeLevel(..)
    | Tick(..) -> Error(Nil)
  }
}

/// A property modifier on the caster, armed from this go: the modifier of an earlier
/// go of the cast is armed again, its timers cancelled and started anew; a row with no
/// delay starts in this step, any other on a timer of its delay, and one that does not
/// last until removed ends on a timer after its delay and duration.
fn caster_modifier_armed(
  cast cast: State,
  row row: spell_plan.PropertyModifier,
  source source: unit_properties.Source,
  change change: CasterChange,
) -> #(State, List(Effect)) {
  {
    let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
    let #(cast, starting) = case row.row.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: ModifierStart(source:, change:),
            after_ms: row.row.delay_ms,
          )
        #(cast, [start])
      }
      False -> #(cast, [CasterChangeStarts(source:, change:)])
    }
    let #(cast, ending) = case row.row.until_removed {
      True -> #(cast, [])
      False -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: ModifierEnd(source:),
            after_ms: row.row.delay_ms + row.row.duration_ms,
          )
        #(cast, [start])
      }
    }
    #(cast, list.flatten([cancels, starting, ending]))
  }
}

/// The heals a go applies: a heal with no delay lands in this step, after the go's
/// 0x7f4, and any other on a timer of its delay (the client adds the delay before it
/// applies a result, `0x1405d77a0`). Each go's heal is its own, so a later go of the cast
/// heals again and no earlier heal is cancelled; a pending heal is dropped with the node
/// of the cast on the caster (`effects_ended`), and lands when the node ends by time
/// (`heals_landed_at_node_end`).
fn heals_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
) -> #(State, List(Effect)) {
  list.fold(aimed.heals, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let healed = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: healed.effect_id)
    let change = Heal(vital: healed.vital, amount: healed.amount)
    case healed.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: ModifierStart(source:, change:),
            after_ms: healed.delay_ms,
          )
        #(cast, list.append(effects, [start]))
      }
      False -> #(
        cast,
        list.append(effects, [CasterChangeStarts(source:, change:)]),
      )
    }
  })
}

/// The cooldown effects a go applies, each armed from this go: the effect of an
/// earlier go of the cast is armed again, its timers cancelled and started anew. A row
/// with no delay takes effect in this step and any other on a timer of its delay. A row
/// is kept for the cooldowns that start later when it is `cooldown_kept`; a kept row is
/// dropped on a timer at the end of its lifetime, unless it never ends.
fn cooldowns_armed(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  longer_of_delay_and_duration longer_of_delay_and_duration: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(aimed.cooldowns, #(cast, []), fn(so_far, entry) {
    let #(cast, effects) = so_far
    let row = entry.0
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, cancels) = cast_state.cancel_source_timers(cast:, source:)
    let lifetime_ms =
      lasting.lifetime_of(row: row.row, longer_of_delay_and_duration:)
    let kept = entry.2
    let #(cast, starting) = case row.row.delay_ms > 0 {
      True -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: CooldownModifierStarts(source:, modifier: row.modifier, kept:),
            after_ms: row.row.delay_ms,
          )
        #(cast, [start])
      }
      False ->
        cooldown_applied(cast:, source:, modifier: row.modifier, kept:, now_ms:)
    }
    let #(cast, ending) = case kept && !row.row.until_removed {
      True -> {
        let #(cast, _, start) =
          cast_state.armed(
            cast:,
            due: CooldownModifierEnds(source:),
            after_ms: lifetime_ms,
          )
        #(cast, [start])
      }
      False -> #(cast, [])
    }
    #(cast, list.flatten([effects, cancels, starting, ending]))
  })
}

/// A cooldown effect takes effect: it is kept for the cooldowns that start later when
/// `kept`, and the running cooldowns it picks change. When one did, a press held for a
/// cooldown and the hold's repeat wait again for the new end (`waits_rearmed`).
fn cooldown_applied(
  cast cast: State,
  source source: unit_properties.Source,
  modifier modifier: cooldown.Modifier,
  kept kept: Bool,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let book = case kept {
    True -> cooldown.keep(book: cast.cooldowns, source:, modifier:)
    False -> cast.cooldowns
  }
  let changed = cooldown.modify(book:, modifier:, now_ms:)
  let cast = State(..cast, cooldowns: changed)
  case changed == book {
    True -> #(cast, [])
    False -> waits_rearmed(cast:, now_ms:)
  }
}

/// The wait of a press held for a cooldown's end and of the held ability's repeat is
/// worked out again after a cooldown moved: each timer is cancelled and started for the
/// new wait, which is a timer of 0 ms when the cooldown ended, so the step's own messages
/// go out first. The press waits for the end wherever it moves (the server's choice,
/// `cast.hold_repeat`).
fn waits_rearmed(
  cast cast: State,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, held) = case cast.held {
    Some(Held(resolution:, until: CooldownEnds, ..)) -> {
      let #(global_left, own_left) =
        cast_cost.cooldown_left_ms(cast:, spell: resolution.spell, now_ms:)
      let #(cast, cancels) =
        cast_state.cancel_timers(cast:, matching: fn(due) { due == StartHeld })
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: StartHeld,
          after_ms: int.max(global_left, own_left),
        )
      #(cast, list.append(cancels, [start]))
    }
    Some(Held(until: CastClears, ..)) | None -> #(cast, [])
  }
  let #(cast, repeating) = case cast.holding {
    Some(Holding(ability:, repeat_timer: Some(_), ..)) ->
      case
        resolved_by_threshold(cast:, bag_spell: ability.spell4_id, ability:)
      {
        Ok(resolution) -> {
          let #(cast, cancels) =
            cast_state.cancel_timers(cast:, matching: fn(due) {
              due == RepeatHeld
            })
          let #(cast, start) =
            repeat_after(
              cast:,
              wait_ms: cooldown_wait_ms(cast:, spell: resolution.spell, now_ms:),
            )
          #(cast, list.append(cancels, start))
        }
        Error(Nil) -> #(cast, [])
      }
    Some(Holding(repeat_timer: None, ..)) | None -> #(cast, [])
  }
  #(cast, list.append(held, repeating))
}

/// The effects of the cast `cast_id` ended when its node on the caster is among the
/// nodes that leave `unit_ids`, whether taken off or ended by time.
fn caster_modifiers_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  effects_ended(cast:, cast_id:, spell:)
}

/// The modifier rows of a spell that change the caster: the rows aimed at struck units
/// are the creature's (`creature_modifiers_ended`).
fn caster_rows(spell spell: Spell) -> List(spell_plan.PropertyModifier) {
  list.filter(spell.modifiers, fn(row) {
    case row.change {
      spell_plan.StruckChange(..) -> False
      spell_plan.PropertyChange(..)
      | spell_plan.LookChange(..)
      | spell_plan.AbsorbChange(..) -> True
    }
  })
}

/// The effects of the cast `cast_id` ended, as its node leaves the caster: each source
/// of its spell's rows has its timers cancelled, and its stealth sources are dropped
/// (`stealth_dropped`). A property modifier that lasts until
/// removed or whose start or end a timer waited for is told ended, and a modifier whose
/// own end already fired is not told again. A cooldown effect is taken out of the kept
/// list; the cooldowns it changed stay changed, as on the client.
fn effects_ended(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
) -> #(State, List(Effect)) {
  let endings =
    list.append(
      list.map(caster_rows(spell:), fn(row) {
        CasterChangeEnding(
          source: unit_properties.Source(cast_id:, effect_id: row.effect_id),
          until_removed: row.row.until_removed,
        )
      }),
      list.map(spell.cooldown_modifiers, fn(row) {
        CooldownEnding(source: unit_properties.Source(
          cast_id:,
          effect_id: row.effect_id,
        ))
      }),
    )
  let #(cast, effects) =
    list.fold(endings, #(cast, []), fn(so_far, ending) {
      let #(cast, effects) = so_far
      let held =
        list.any(dict.values(cast.timers), fn(due) {
          cast_state.source_of(due:) == Some(ending.source)
        })
      let #(cast, cancels) =
        cast_state.cancel_source_timers(cast:, source: ending.source)
      case ending {
        CasterChangeEnding(source:, until_removed:) if until_removed || held -> #(
          cast,
          list.flatten([effects, cancels, [CasterChangeEnds(source:)]]),
        )
        CasterChangeEnding(..) -> #(cast, list.append(effects, cancels))
        CooldownEnding(source:) -> #(
          State(..cast, cooldowns: cooldown.drop(book: cast.cooldowns, source:)),
          list.append(effects, cancels),
        )
      }
    })
  let #(cast, heal_cancels) = pending_heals_cancelled(cast:, cast_id:)
  let #(restrictions, others) = split_cast(held: cast.restrictions, cast_id:)
  let cast = State(..cast, restrictions: others)
  let #(cast, restriction_cancels) =
    cast_state.cancel_timers(cast:, matching: fn(due) {
      case due {
        RestrictionEnd(source:) | ProcDue(source:, ..) ->
          source.cast_id == cast_id
        Go(..)
        | Finish(..)
        | StartChild(..)
        | NodesEnd(..)
        | StateEnd(..)
        | ModifierStart(..)
        | TargetModifierStart(..)
        | ForcedMoveStart(..)
        | ModifierEnd(..)
        | CooldownModifierStarts(..)
        | CooldownModifierEnds(..)
        | StartHeld
        | RepeatHeld
        | WindowEnd(..)
        | ChargeLevel(..)
        | Tick(..) -> False
      }
    })
  #(
    procs_dropped(cast: stealth_dropped(cast:, cast_id:), cast_id:),
    list.flatten([
      effects,
      heal_cancels,
      restriction_cancels,
      restrictions_ended(held: restrictions, cast_id:),
    ]),
  )
}

/// The heals of the cast `cast_id` that a timer still waits to land, by timer id.
fn pending_heals(
  cast cast: State,
  cast_id cast_id: Int,
) -> List(#(TimerId, unit_properties.Source, effect_kind.Vital, Int)) {
  cast_state.timers_in_order(cast:)
  |> list.filter_map(fn(entry) {
    case entry.1 {
      ModifierStart(source:, change: Heal(vital:, amount:))
        if source.cast_id == cast_id
      -> Ok(#(entry.0, source, vital, amount))
      ModifierStart(..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> Error(Nil)
    }
  })
}

/// The pending heals of the cast `cast_id` cancelled with their timers: the node
/// of the cast on the caster is gone, and the client's 0x811 or 0x7fe destroys the effect
/// still pending (`opcode.0x7fe`).
fn pending_heals_cancelled(
  cast cast: State,
  cast_id cast_id: Int,
) -> #(State, List(Effect)) {
  cast_state.cancel_timers(cast:, matching: fn(due) {
    case due {
      ModifierStart(source:, change: Heal(..)) -> source.cast_id == cast_id
      ModifierStart(change: Property(..), ..)
      | ModifierStart(change: Absorb(..), ..)
      | ModifierStart(change: Look(..), ..)
      | TargetModifierStart(..)
      | ForcedMoveStart(..)
      | ModifierEnd(..)
      | RestrictionEnd(..)
      | CooldownModifierStarts(..)
      | CooldownModifierEnds(..)
      | ProcDue(..)
      | Go(..)
      | Finish(..)
      | StartChild(..)
      | NodesEnd(..)
      | StateEnd(..)
      | StartHeld
      | RepeatHeld
      | WindowEnd(..)
      | ChargeLevel(..)
      | Tick(..) -> False
    }
  })
}

/// The heals of the cast `cast_id` that a timer still waits to land, landed now,
/// as the caster's node ends by time: a node lives as long as its longest effect, so a
/// heal's start falls in the millisecond of the node's end or before it, and the end
/// applies it first, whichever timer the shell delivers first. A node taken off lands
/// none (`effects_ended`).
fn heals_landed_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  let pending = pending_heals(cast:, cast_id:)
  let #(cast, cancels) = pending_heals_cancelled(cast:, cast_id:)
  #(
    cast,
    list.append(
      cancels,
      list.map(pending, fn(heal) {
        CasterChangeStarts(
          source: heal.1,
          change: Heal(vital: heal.2, amount: heal.3),
        )
      }),
    ),
  )
}

/// The stealth sources of the cast `cast_id` dropped, as its node leaves the caster: the
/// stealth lasts as long as the node that holds it.
fn stealth_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, stealth: without_cast(held: cast.stealth, cast_id:))
}

/// What a cast holds by source (its stealth sources, its procs) with the entries of the
/// cast `cast_id` left out.
fn without_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> Dict(unit_properties.Source, a) {
  dict.filter(held, fn(source, _) { source.cast_id != cast_id })
}

/// What a cast holds by source, split in the entries of the cast `cast_id` and what is
/// left of it.
fn split_cast(
  held held: Dict(unit_properties.Source, a),
  cast_id cast_id: Int,
) -> #(List(#(unit_properties.Source, a)), Dict(unit_properties.Source, a)) {
  let #(of_cast, others) =
    dict.to_list(held)
    |> list.partition(fn(entry) { { entry.0 }.cast_id == cast_id })
  #(of_cast, dict.from_list(others))
}

/// The Proc rows of the cast `cast_id` dropped, as its node leaves the caster: a proc is
/// held as long as the node that holds it.
fn procs_dropped(cast cast: State, cast_id cast_id: Int) -> State {
  State(..cast, procs: without_cast(held: cast.procs, cast_id:))
}

/// The cooldown effects of the cast `cast_id` that a timer still waits to start, taken
/// effect as the caster's node ends by time, because a node lives at least as long as
/// every row's delay from the same go, so the row's start falls in the millisecond of
/// the node's end or before it. A node taken off, by a removal, a death or a leave, does
/// not apply them: the client's 0x811 or 0x7fe destroys the pending effect.
fn cooldowns_started_at_node_end(
  cast cast: State,
  cast_id cast_id: Int,
  spell spell: Spell,
  unit_ids unit_ids: List(Int),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: !list.contains(unit_ids, cast_state.caster_of(cast_id:)),
    return: #(cast, []),
  )
  list.fold(spell.cooldown_modifiers, #(cast, []), fn(so_far, row) {
    let #(cast, effects) = so_far
    let source = unit_properties.Source(cast_id:, effect_id: row.effect_id)
    let #(cast, cancels) =
      cast_state.cancel_timers(cast:, matching: fn(due) {
        due
        == CooldownModifierStarts(source:, modifier: row.modifier, kept: False)
      })
    case cancels {
      [] -> #(cast, effects)
      [_, ..] -> {
        let #(cast, applied) =
          cooldown_applied(
            cast:,
            source:,
            modifier: row.modifier,
            kept: False,
            now_ms:,
          )
        #(cast, list.flatten([effects, cancels, applied]))
      }
    }
  })
}

/// The nodes a go gives, one for each unit a Fluff row aims at or a crowd-control state
/// landed on: count 1 and the longest life of its rows with the effects the cast's node on
/// the unit already holds (`lasting.given`: a later go keeps and re-arms them, as on the
/// client, `opcode.0x7f4.instance_count`), and at least until the time the creature
/// holds each state, which no later go moves; a unit left with no effect that has a life
/// and no state holds no node of the cast.
fn nodes_given(
  cast cast: State,
  cast_id cast_id: Int,
  aimed aimed: Aimed,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case dict.get(cast.casts, cast_id), nodes_aimed(aimed:) {
    Error(Nil), _ | _, [] -> #(cast, [])
    Ok(live), units -> {
      let given =
        units
        |> list.map(fn(unit_id) {
          #(
            unit_id,
            node_of(
              spell: live.spell,
              held: dict.get(live.nodes, unit_id) |> option.from_result,
              aimed:,
              unit_id:,
              now_ms:,
            ),
          )
        })
      let #(cast, pushed) =
        list.fold(given, #(cast, []), fn(so_far, entry) {
          case entry.1 {
            Ok(node) -> pushed_by(so_far:, cast_id:, live:, node:, now_ms:)
            Error(Nil) -> so_far
          }
        })
      let nodes = case dict.get(cast.casts, cast_id) {
        Ok(current) -> current.nodes
        Error(Nil) -> live.nodes
      }
      let nodes =
        list.fold(given, nodes, fn(nodes, entry) {
          case entry.1 {
            Ok(node) -> dict.insert(nodes, entry.0, node)
            Error(Nil) -> dict.delete(nodes, entry.0)
          }
        })
      #(with_nodes(cast:, cast_id:, nodes:), pushed)
    }
  }
}

/// The units a go gives a node: those a Fluff row aims at, those that took a
/// crowd-control state and those a periodic row ticks on, each once, in that order. The state's life is its delay plus
/// its duration, so the caster's cast lingers until the state's effect is over and its
/// time readout stays right (`cc_state.end`).
fn nodes_aimed(aimed aimed: Aimed) -> List(Int) {
  list.unique(
    list.flatten([
      list.map(aimed.lasting, fn(entry) { entry.1 }),
      list.map(aimed.modifiers, fn(entry) { entry.1 }),
      list.map(aimed.cooldowns, fn(entry) { entry.1 }),
      list.map(aimed.stealth, fn(entry) { entry.1 }),
      list.map(aimed.procs, fn(entry) { entry.1 }),
      list.map(aimed.heals, fn(entry) { entry.1 }),
      list.map(aimed.controls, fn(entry) { entry.1 }),
      list.map(aimed.restrictions, fn(entry) { entry.1 }),
      list.map(aimed.ticking, fn(row) { row.unit_id }),
    ]),
  )
}

/// The node a go gives one unit from the node its cast holds there and the Fluff rows
/// the go lists for it (`lasting.given`), a periodic row living its own delay and
/// durationTime as the client's node does (`opcode.0x7f4.effect_time`), held past that
/// only while a tick round on the unit is open (`ended_and_kept`); none when no effect has
/// a life.
fn node_of(
  spell spell: Spell,
  held held: Option(lasting.Node),
  aimed aimed: Aimed,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> Result(lasting.Node, Nil) {
  let rows =
    list.flatten([
      list.filter_map(aimed.lasting, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.modifiers, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.cooldowns, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.stealth, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.procs, fn(entry) {
        case entry.1 == unit_id {
          True -> Ok(entry.0.row)
          False -> Error(Nil)
        }
      }),
      list.filter_map(aimed.heals, fn(entry) {
        case entry.1 == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: { entry.0 }.delay_ms,
              duration_ms: 0,
              until_removed: False,
            ))
          False -> Error(Nil)
        }
      }),
    ])
  let rows =
    list.append(
      rows,
      list.filter_map(aimed.restrictions, fn(entry) {
        case entry.1 == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: entry.0.row.row.delay_ms,
              duration_ms: entry.0.row.row.duration_ms,
              until_removed: entry.0.row.row.until_removed,
            ))
          False -> Error(Nil)
        }
      }),
    )
    |> list.append(
      list.filter_map(aimed.ticking, fn(row) {
        case row.unit_id == unit_id {
          True ->
            Ok(lasting.LastingRow(
              delay_ms: row.schedule.delay_ms,
              duration_ms: row.schedule.duration_ms,
              until_removed: False,
            ))
          False -> Error(Nil)
        }
      }),
    )
  let held_until_ms =
    list.filter_map(aimed.controls, fn(entry) {
      case entry.1 == unit_id {
        True -> Ok(entry.0.ends_at_ms)
        False -> Error(Nil)
      }
    })
  lasting.given(
    held:,
    unit_id:,
    count: 1,
    effects: rows,
    held_until_ms:,
    longer_of_delay_and_duration: spell.longer_of_delay_and_duration,
    go_ms: now_ms,
  )
}

/// A node the go gives a unit its cast holds none on yet makes a new cast on that
/// unit, which pushes the caster's oldest casts of its stack off the unit at the cap
/// (Jim's decision, `lasting.pushed_off`); a unit the cast holds a node on already is a
/// later go of the same cast, which pushes nothing.
fn pushed_by(
  so_far so_far: #(State, List(Effect)),
  cast_id cast_id: Int,
  live live: Live,
  node node: lasting.Node,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  use <- bool.guard(
    when: dict.has_key(live.nodes, node.unit_id),
    return: so_far,
  )
  let #(cast, effects) = so_far
  let removals =
    lasting.pushed_off(
      holds: list.filter(holds_on(cast:, unit_id: node.unit_id), fn(hold) {
        hold.cast_id != cast_id
      }),
      spell4_id: live.spell.spell4_id,
      stack: live.spell.stack,
      unit_id: node.unit_id,
    )
  let #(cast, more) = apply_removals(cast:, removals:, now_ms:)
  #(cast, list.append(effects, more))
}

/// What the live and lingering casts hold on the unit, as removals, stacking and
/// prerequisites read it.
pub fn holds_on(cast cast: State, unit_id unit_id: Int) -> List(lasting.Hold) {
  list.filter_map(cast_state.holders(cast:), fn(entry) {
    let #(cast_id, holder) = entry
    dict.get(holder.nodes, unit_id)
    |> result.map(fn(node) {
      lasting.Hold(
        cast_id:,
        spell4_id: holder.spell.spell4_id,
        base: holder.spell.spell4_base_id,
        groups: holder.spell.groups,
        stack: holder.spell.stack,
        started_ms: holder.started_ms,
        node:,
      )
    })
  })
}

/// What a removal does to the casts, in order: a cast that loses its whole node on a
/// unit is written 0x811 and keeps no node there, one that loses a stack is written
/// 0x813 and keeps its node one count lower. A lingering cast left with no node is
/// dropped, and, when its cast method is one the client keeps with no target
/// (Channeled, ChanneledField, Multiphase or 10), ends with its 0x7fe after the 0x811
/// (`opcode.0x811`).
fn apply_removals(
  cast cast: State,
  removals removals: List(lasting.Removal),
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  list.fold(removals, #(cast, []), fn(so_far, removal) {
    let #(cast, effects) = so_far
    let #(cast, more) = case removal {
      lasting.NodeOff(cast_id:, unit_id:) ->
        node_off(cast:, cast_id:, unit_id:, now_ms:)
      lasting.StackOff(cast_id:, unit_id:) ->
        stack_off(cast:, cast_id:, unit_id:)
    }
    #(cast, list.append(effects, more))
  })
}

/// A cast loses its whole node on a unit: 0x811 for the unit, with the cast destroyed on
/// the client when it has no node left and its method is not one the client keeps; a
/// lingering cast with none left is dropped, with its 0x7fe after the 0x811 when the
/// client keeps a cast of its method.
fn node_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let #(cast, ticks) = ticks_dropped(cast:, cast_id:, unit_id:)
      let nodes = dict.delete(holder.nodes, unit_id)
      let emptied = dict.is_empty(nodes)
      let kept = keeps_without_target(method: holder.spell.method)
      let removed =
        targets_removed_effects(
          cast_id:,
          unit_ids: [unit_id],
          audience: holder.audience,
          destroyed: emptied && !kept,
        )
      let #(cast, modifiers) =
        caster_modifiers_ended(cast:, cast_id:, spell: holder.spell, unit_ids: [
          unit_id,
        ])
      let #(cast, on_creatures) =
        creature_modifiers_ended(cast:, cast_id:, unit_ids: [unit_id])
      let #(cast, left) = nodes_left(cast:, cast_id:, holder:, nodes:, now_ms:)
      let ends = case holder.lingering && emptied && kept {
        True -> finished_effects(cast_id:, audience: holder.audience)
        False -> []
      }
      #(
        cast,
        list.flatten([ticks, removed, modifiers, on_creatures, left, ends]),
      )
    }
  }
}

/// Whether the client keeps a cast that has no target left, so its end must be
/// written (`opcode.0x811`: cast methods 1, 3, 8 and 10).
fn keeps_without_target(method method: spell_plan.CastMethod) -> Bool {
  case method {
    spell_plan.Channeled
    | spell_plan.ChanneledField
    | spell_plan.Multiphase
    | spell_plan.OtherMethod(10) -> True
    spell_plan.Normal
    | spell_plan.PressHold
    | spell_plan.ClientSideInteraction
    | spell_plan.RapidTap
    | spell_plan.ChargeRelease
    | spell_plan.Transactional
    | spell_plan.OtherMethod(..) -> False
  }
}

/// A cast loses one stack on a unit: 0x813 and its node one count lower. A node's
/// count is the 1 of an application, so a removal reaches this only for a node whose
/// count is higher (`opcode.0x7f4.instance_count`, `opcode.0x813`).
fn stack_off(
  cast cast: State,
  cast_id cast_id: Int,
  unit_id unit_id: Int,
) -> #(State, List(Effect)) {
  case cast_state.holder_of(cast:, cast_id:) {
    Error(Nil) -> #(cast, [])
    Ok(holder) -> {
      let nodes = case dict.get(holder.nodes, unit_id) {
        Ok(node) ->
          dict.insert(
            holder.nodes,
            unit_id,
            lasting.Node(..node, count: int.max(0, node.count - 1)),
          )
        Error(Nil) -> holder.nodes
      }
      #(
        with_nodes(cast:, cast_id:, nodes:),
        stack_removed_effects(cast_id:, unit_id:, audience: holder.audience),
      )
    }
  }
}

/// 0x811 for the units, to the caster and told to the audience, with whether the
/// client destroys the cast with it.
fn targets_removed_effects(
  cast_id cast_id: Int,
  unit_ids unit_ids: List(Int),
  audience audience: Set(ConnectionId),
  destroyed destroyed: Bool,
) -> List(Effect) {
  let removed = SpellTargetsRemoved(cast_id:, unit_ids:)
  [
    Send(frame: cast_frame.targets_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(
        to: viewer,
        news: client_connection.CastTargetsRemoved(removed:, destroyed:),
      )
    })
  ]
}

/// 0x813 for the unit, to the caster and told to the audience.
fn stack_removed_effects(
  cast_id cast_id: Int,
  unit_id unit_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  let removed = SpellStackRemoved(cast_id:, unit_id:)
  [
    Send(frame: cast_frame.stack_removed_frame(removed:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastStackRemoved(removed:))
    })
  ]
}

/// 0x7fe to the caster and told to the audience.
fn finished_effects(
  cast_id cast_id: Int,
  audience audience: Set(ConnectionId),
) -> List(Effect) {
  [
    Send(frame: cast_frame.finished_frame(cast_id:)),
    ..list.map(map.sorted_connections(audience), fn(viewer) {
      Tell(to: viewer, news: client_connection.CastFinished(cast_id:))
    })
  ]
}

/// What a prerequisite may read about the caster, with no roll: the live casts it is
/// the primary target of and what the live and lingering casts hold on it, whether it
/// is in combat, and its vitals: its health and
/// shield, and the one class resource slot it holds as Vital 5 to 11 (slots 0 to 6,
/// `0x1403b3320`: the cost check reads Vitals 5 to 11 as the caster's resource slots
/// 0 to 6; the getter type 71 and 73 call is not read case by case, so the same
/// mapping is taken for it). A slot the class does not hold is no vital, so a
/// prerequisite of it is not read. The same slot is the resource slot a type 64 condition
/// names by its number, and every other slot reads 0.0 as the client's unit holds it
/// (`class_resource`, `0x140454380`). A player holds no difficulty. The caster stands on
/// its own point, facing its own yaw, for both units of a type 108 condition
/// (`Spell4Effects.prerequisiteIdTargetApply`: the caster is both units of a caster-side
/// check).
pub fn subject_of(
  cast cast: State,
  caster caster: Caster,
) -> prerequisite.Subject {
  let slot = class_resource.slot(resources: caster.resources)
  let held = case slot >= 0 && slot <= 6 {
    True -> [
      #(
        slot + 5,
        prerequisite.Vital(
          current: class_resource.value(resources: caster.resources, slot:),
          maximum: class_resource.max(resources: caster.resources, slot:),
        ),
      ),
    ]
    False -> []
  }
  let pose = area.pose_of(place: caster.place)
  prerequisite.Subject(
    under: dict.values(cast.casts)
      |> list.filter(fn(live) { live.primary_target == caster.unit_id })
      |> list.map(fn(live) {
        lasting.Held(
          spell4_id: live.spell.spell4_id,
          caster: caster.unit_id,
          count: 0,
          groups: live.spell.groups,
        )
      })
      |> list.append(nodes_held(cast:, caster:)),
    second_unit: Some(caster.unit_id),
    in_combat: caster.in_combat,
    vitals: dict.merge(dict.from_list(held), caster.life_vitals),
    difficulty: None,
    stealthed: Some(cast_state.stealthed(cast:)),
    resource_slots: Some(case slot >= 0 {
      True ->
        dict.from_list([
          #(slot, class_resource.value(resources: caster.resources, slot:)),
        ])
      False -> dict.new()
    }),
    rolls: [],
    positions: prerequisite.Placed(first: pose, second: pose),
    factions: Some(caster.factions),
    player: Some(caster.player),
    quests: Some(caster.quests),
    creature_index: None,
    seen: prerequisite.WholeUnit,
    checker: Some(caster.checker),
    first_unit: prerequisite.TheChecker,
  )
}

/// What the live and lingering casts hold on the caster's own unit, as a
/// prerequisite reads it.
fn nodes_held(cast cast: State, caster caster: Caster) -> List(lasting.Held) {
  list.map(holds_on(cast:, unit_id: caster.unit_id), fn(hold) {
    lasting.Held(
      spell4_id: hold.spell4_id,
      caster: caster.unit_id,
      count: hold.node.count,
      groups: hold.groups,
    )
  })
}

/// A Proxy of a go: a Proxy aimed at the area starts one child for each Hit unit of
/// the round and none for a deflect, any other starts one on the caster. A Proxy behind a
/// target gate starts a child on a unit only when the gate passes against that unit, once
/// for each unit, in the order of the units, each check taking the rolls its gate needs
/// (`target_gate`); the rolls left follow the effects.
fn children(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  struck struck: List(Struck),
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(State, List(Effect), List(Int)) {
  let targets = case proxy.target {
    spell_plan.OnCaster -> [caster.unit_id]
    spell_plan.OnEachStruck -> cast_gate.hit_units(struck:)
  }
  list.fold(targets, #(cast, [], rolls), fn(so_far, primary_target) {
    let #(cast, effects, rolls) = so_far
    let #(gate, rolls) =
      target_gate(
        cast:,
        proxy:,
        caster:,
        primary_target:,
        subject:,
        poses:,
        indexes:,
        units:,
        rolls:,
      )
    case gate {
      Starts -> {
        let #(cast, more) =
          child(cast:, caster:, now_ms:, live:, proxy:, primary_target:)
        #(cast, list.append(effects, more), rolls)
      }
      GateFails -> #(cast, effects, rolls)
      CannotTell(why:) -> #(
        cast,
        list.append(effects, [Log(level: LogDebug, text: why)]),
        rolls,
      )
    }
  })
}

/// The subject of a Proxy's target gate on a struck unit: as the caster's picture shows it,
/// with the checklist index its 0x262 carried when the picture holds one, what the unit is
/// (a unit the picture does not hold is unknown to a type 38 or 214 condition), and what
/// the caster's own casts hold on it (a type 130 condition's group).
fn struck_subject(
  cast cast: State,
  caster caster: Caster,
  primary_target primary_target: Int,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
) -> prerequisite.Subject {
  let struck =
    prerequisite.of_struck(
      first: option.from_result(dict.get(poses, primary_target)),
      second: area.pose_of(place: caster.place),
      player: caster.player,
      quests: caster.quests,
      unit: result.unwrap(
        dict.get(units, primary_target),
        or: prerequisite.UnknownUnit,
      ),
      caster_unit: caster.unit_id,
      under: held_by_caster_on(cast:, caster:, unit_id: primary_target),
      checker: caster.checker,
    )
  case dict.get(indexes, primary_target) {
    Ok(index) -> prerequisite.counting(subject: struck, checklist_index: index)
    Error(Nil) -> struck
  }
}

/// What a Proxy's target gate gives for the unit its child would be made on. The gate's
/// first unit is that unit and its second the caster
/// (`Spell4Effects.prerequisiteIdTargetApply`): a struck unit as the caster's picture
/// shows it (`of_struck`, so a unit with no pose leaves a type 108 condition not read), or
/// the caster for a Proxy aimed at it, which stands on its own point, as `subject` has it.
/// A Proxy with no target gate starts. The plan gives a Proxy no condition but `Always`,
/// `GatedOnCaster` and `GatedOnCasterAndTarget`; a Proxy that holds `GatedOnTarget`, which
/// it never builds for one, starts on a unit that passes the gate, as any row does. The
/// check takes the rolls of its type 37 conditions off the front of `rolls`, and the rolls
/// left follow the verdict.
fn target_gate(
  cast cast: State,
  proxy proxy: Proxy,
  caster caster: Caster,
  primary_target primary_target: Int,
  subject subject: prerequisite.Subject,
  poses poses: Dict(Int, area.Pose),
  indexes indexes: Dict(Int, Int),
  units units: Dict(Int, prerequisite.FirstUnit),
  rolls rolls: List(Int),
) -> #(GateDecision, List(Int)) {
  case proxy.condition {
    spell_plan.GatedOnTarget(prerequisite: target)
    | spell_plan.GatedOnCasterAndTarget(target:, ..) -> {
      let gate_subject = case proxy.target {
        spell_plan.OnCaster -> subject
        spell_plan.OnEachStruck ->
          struck_subject(
            cast:,
            caster:,
            primary_target:,
            poses:,
            indexes:,
            units:,
          )
      }
      cast_gate.unit_gate(
        target:,
        unit_id: primary_target,
        target_verdict: fn(gate, _, rolls) {
          cast_gate.checked(prerequisite: gate, subject: gate_subject, rolls:)
        },
        what: "the Proxy to Spell4 "
          <> int.to_string(proxy.spell.spell4_id.value),
        outcome: "so it is not started",
        rolls:,
      )
    }
    spell_plan.Always | spell_plan.GatedOnCaster(..) -> #(Starts, rolls)
  }
}

/// One child of a Proxy: it starts at once for no delay, else after it from a timer
/// of its own. The Proxy's gate has passed at the go (`proxy_gates`).
fn child(
  cast cast: State,
  caster caster: Caster,
  now_ms now_ms: Int,
  live live: Live,
  proxy proxy: Proxy,
  primary_target primary_target: Int,
) -> #(State, List(Effect)) {
  case proxy.delay_ms > 0 {
    False ->
      start(
        cast:,
        caster:,
        now_ms:,
        spell: proxy.spell,
        root: live.root,
        parent: Some(live.spell.spell4_id),
        primary_target:,
        client_cast_id: None,
        role: Child,
        spent: None,
        reserved: [],
      )
    True -> {
      let #(cast, _, start) =
        cast_state.armed(
          cast:,
          due: StartChild(
            root: live.root,
            parent: live.spell.spell4_id,
            primary_target:,
            proxy:,
          ),
          after_ms: proxy.delay_ms,
        )
      #(cast, [start])
    }
  }
}

/// A live cast ends: 0x7fe to the caster and the audience, and the cast is no
/// longer live nor the caster's current cast. A channel starts its cooldown here
/// too (`0x14053e1b0`), and a stage that closes its ability's threshold does that
/// after its 0x7fe.
fn finish(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(cast, ticks) = ticks_all_dropped(cast:, cast_id:)
  let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
  #(
    passive_cleared(cast:, cast_id:),
    list.flatten([
      ticks,
      finished_effects(cast_id:, audience: live.audience),
      closed,
    ]),
  )
}

/// The cast without the innate passive's id when the cast `cast_id` is the passive and
/// has left both `casts` and `lingering`, so that no later cast the caster mints the
/// same id for is taken for the passive.
fn passive_cleared(cast cast: State, cast_id cast_id: Int) -> State {
  use <- bool.guard(when: cast.passive != Some(cast_id), return: cast)
  State(..cast, passive: None)
}

/// Every step of a live cast's end but its 0x7fe: the cast is no longer live nor the
/// caster's current cast, a channel starts its cooldown (`0x14053e1b0`), and a stage
/// that closes its ability's threshold does that, with what the close writes.
fn finish_steps(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let cast =
    State(
      ..cast,
      casts: dict.delete(cast.casts, cast_id),
      current: case cast.current == Some(cast_id) {
        True -> None
        False -> cast.current
      },
    )
  let cast = case live.spell.method, live.spell.cooldown_phase {
    spell_plan.Channeled, _ -> start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, Some(phase) if live.gone > phase ->
      start_cooldown(cast:, spell: live.spell, now_ms:)
    spell_plan.Multiphase, _ -> cast
    spell_plan.Normal, _
    | spell_plan.PressHold, _
    | spell_plan.ChanneledField, _
    | spell_plan.ClientSideInteraction, _
    | spell_plan.RapidTap, _
    | spell_plan.ChargeRelease, _
    | spell_plan.Transactional, _
    | spell_plan.OtherMethod(..), _
    -> cast
  }
  case live.stage_of, live.closes_threshold {
    Some(ability), True -> close_threshold(cast:, ability:, now_ms:)
    Some(_), False | None, True | None, False -> #(cast, [])
  }
}

/// A live cast that has gone for the last time ends, or lingers when a node of it
/// still has life: every step of its end runs, and only its 0x7fe waits until its
/// last node ends (`cast.target_node_end`). A node whose life is over when the cast
/// starts to linger is written 0x811 at once. The innate passive's cast lingers even
/// when no node of it lives, so it ends with no 0x7fe, and only when its last node is
/// taken off.
fn finish_or_linger(
  cast cast: State,
  cast_id cast_id: Int,
  live live: Live,
  now_ms now_ms: Int,
) -> #(State, List(Effect)) {
  let #(ended, kept) =
    ended_and_kept(nodes: live.nodes, ticking: live.ticking, now_ms:)
  case kept, cast.passive == Some(cast_id) {
    [], False -> finish(cast:, cast_id:, live:, now_ms:)
    [], True | [_, ..], _ -> {
      let #(cast, closed) = finish_steps(cast:, cast_id:, live:, now_ms:)
      let cast =
        State(
          ..cast,
          lingering: dict.insert(
            cast.lingering,
            cast_id,
            Lingering(
              spell: live.spell,
              audience: live.audience,
              started_ms: live.started_ms,
              primary_target: live.primary_target,
              nodes: dict.from_list(kept),
              ticking: live.ticking,
            ),
          ),
        )
      let #(cast, ticks) =
        ticks_dropped_on(
          cast:,
          cast_id:,
          unit_ids: cast_state.sorted_units(ended),
        )
      let #(cast, armed) = rearmed(cast:, cast_id:, now_ms:)
      let expired = case ended {
        [] -> []
        [_, ..] ->
          targets_removed_effects(
            cast_id:,
            unit_ids: cast_state.sorted_units(ended),
            audience: live.audience,
            destroyed: False,
          )
      }
      #(cast, list.flatten([ticks, expired, armed, closed]))
    }
  }
}
