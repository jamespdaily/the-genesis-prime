//// The respawn gaps of the fight load run's `respawning` scene (`genesis_prime/load_fight`),
//// counted from what a walker was sent. Pure: the walker tells each message it is sent
//// and when, and a test plants them.
////
//// ```
//// a message sent to the walker ─▶ told ─▶ Gaps: removals waiting, gaps, deaths
//// every walker's Gaps, when they stopped ─▶ seen, needed ─▶ the respawns counted, and the fewest the run needs
//// ```
////
//// - A walker is told a unit's removal in the creature's own news (`Removed`) or the map's
////   notices (`UnitUnseen`, `Gone`, `ObjectsUnseen`), and a unit's creation in the creature's
////   own news (`CreatureAppeared`) or the map's notice (`ObjectsSeen`), so each form
////   counts (`unit_news.News`, `map.Notice`). A message about a player's unit is neither.
//// - A respawn is a unit's removal and then its next creation; its gap is the time between
////   the two as the walker was sent them. A creation with no removal before it is no respawn,
////   and a second creation after one removal is not another.
//// - A death is a creature's `Died` news.
//// - The gate's minimum is 1, or the creatures killed that were owed one if more: a death
////   within `settle_us` of the walkers' end is not owed one, since the corpse timer and the
////   next life are still to come.

import genesis_prime/client_connection.{
  type StaySent, SentByFoe, SentByKill, SentByLine, SentByMap, SentByMove,
  SentByPeer, SentByPlayer, SentByTarget,
}
import genesis_prime/game/unit_news.{type News, PeerNews}
import genesis_prime/world_map/map.{type Notice}
import genesis_prime/world_map/static_object
import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/pair

/// What one walker counted of the units it saw die, vanish and appear: when each unit's
/// removal was told, the gap of each respawn and the time of each death, in microseconds.
pub type Gaps {
  Gaps(
    removed_at_us: Dict(Int, Int),
    gaps_us: List(Int),
    deaths_at_us: List(Int),
  )
}

/// Nothing seen yet.
pub fn none() -> Gaps {
  Gaps(removed_at_us: dict.new(), gaps_us: [], deaths_at_us: [])
}

/// What a message tells of the units' lives.
type Told {
  Removal(unit_ids: List(Int))
  Creation(unit_ids: List(Int))
  Death
  Unrelated
}

/// The gaps after the walker was sent `sent` at `at_us`.
pub fn told(gaps gaps: Gaps, sent sent: StaySent, at_us at_us: Int) -> Gaps {
  case of_sent(sent) {
    Removal(unit_ids:) ->
      Gaps(
        ..gaps,
        removed_at_us: list.fold(unit_ids, gaps.removed_at_us, fn(removed, id) {
          dict.insert(removed, id, at_us)
        }),
      )
    Creation(unit_ids:) ->
      list.fold(unit_ids, gaps, fn(gaps, id) {
        created(gaps:, unit_id: id, at_us:)
      })
    Death -> Gaps(..gaps, deaths_at_us: [at_us, ..gaps.deaths_at_us])
    Unrelated -> gaps
  }
}

/// The gaps after the unit `unit_id` was created at `at_us`: a respawn when its removal
/// was waiting.
fn created(gaps gaps: Gaps, unit_id unit_id: Int, at_us at_us: Int) -> Gaps {
  case dict.get(gaps.removed_at_us, unit_id) {
    Ok(removed_us) ->
      Gaps(
        ..gaps,
        removed_at_us: dict.delete(gaps.removed_at_us, unit_id),
        gaps_us: [at_us - removed_us, ..gaps.gaps_us],
      )
    Error(Nil) -> gaps
  }
}

fn of_sent(sent: StaySent) -> Told {
  case sent {
    SentByPeer(news: PeerNews(unit_id:, news:)) -> of_news(unit_id:, news:)
    SentByMap(notice:) -> of_notice(notice)
    SentByMove(..)
    | SentByFoe(..)
    | SentByTarget(..)
    | SentByPlayer(..)
    | SentByKill(..)
    | SentByLine(..) -> Unrelated
  }
}

fn of_notice(notice: Notice) -> Told {
  case notice {
    map.UnitUnseen(unit_id:, ..) | map.Gone(unit_id:) -> Removal([unit_id])
    map.ObjectsUnseen(unit_ids:) -> Removal(unit_ids)
    map.ObjectsSeen(units:) ->
      Creation(
        list.map(units, fn(unit) {
          static_object.unit_id(created: pair.second(unit))
        }),
      )
    map.SeenBy(..) | map.UnseenBy(..) -> Unrelated
  }
}

fn of_news(unit_id unit_id: Int, news news: News) -> Told {
  case news {
    unit_news.Removed -> Removal([unit_id])
    unit_news.CreatureAppeared(..) -> Creation([unit_id])
    unit_news.Died -> Death
    unit_news.Appeared(..)
    | unit_news.Departed(..)
    | unit_news.CastStarted(..)
    | unit_news.CastWent(..)
    | unit_news.CastMissed(..)
    | unit_news.CastTicked(..)
    | unit_news.CastTargetsRemoved(..)
    | unit_news.CastStackRemoved(..)
    | unit_news.CastFinished(..)
    | unit_news.CastInterrupted(..)
    | unit_news.Health(..)
    | unit_news.CameBack
    | unit_news.DeathLogged
    | unit_news.CameBackLogged
    | unit_news.CreatureMoved(..)
    | unit_news.CreaturePlaced(..)
    | unit_news.CreatureFaces(..)
    | unit_news.Targeting(..)
    | unit_news.Threat(..)
    | unit_news.CombatState(..)
    | unit_news.Shield(..)
    | unit_news.InterruptArmor(..)
    | unit_news.Absorption(..)
    | unit_news.Level(..)
    | unit_news.CrowdControlApplied(..)
    | unit_news.CrowdControlEnded(..)
    | unit_news.CasterRestrictionApplied(..)
    | unit_news.CasterRestrictionEnded(..)
    | unit_news.UnitStateHeld(..)
    | unit_news.UnitStateEnded(..)
    | unit_news.PropertiesChanged(..)
    | unit_news.Stealth(..)
    | unit_news.LookChanged(..)
    | unit_news.HeldCastEnded(..)
    | unit_news.HeldCastStarted(..) -> Unrelated
  }
}

/// The respawns the walkers counted.
pub fn seen(all all: List(Gaps)) -> Int {
  list.fold(all, 0, fn(sum, one) { sum + list.length(one.gaps_us) })
}

/// The fewest respawns a run needs: as many as the creatures killed that were owed one, and
/// at least 1. `ended_us` is when the walkers stopped, and a death within `settle_us` of it
/// is not owed a respawn yet.
pub fn needed(
  all all: List(Gaps),
  ended_us ended_us: Int,
  settle_us settle_us: Int,
) -> Int {
  let killed =
    list.fold(all, 0, fn(sum, one) {
      sum
      + list.count(one.deaths_at_us, fn(at_us) { at_us <= ended_us - settle_us })
    })
  int.max(1, killed)
}
