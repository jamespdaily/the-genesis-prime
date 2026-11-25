//// What a refusal of the plan says (`genesis_prime/game/spell_plan` `refusal_of`): whether the
//// ability that holds it is left out or the load fails, and why the server refuses the value.
//// Expected values come from `plan_error_samples`, whose rows name their sources: the
//// outcomes are what the plan did before the refusal was one decision, and each basis
//// is the fact file's record (its grade and a phrase of its gap) or the code that raises the
//// error. No client files are read.

import code_rule/source.{SourceFile}
import code_rule/syntax
import coverage_support
import fact_file
import genesis_prime/game/prerequisite
import genesis_prime/game/spell_plan.{
  type Basis, FailsLoad, LeavesOut, OpenQuestion, Unexplained,
}
import glance
import gleam/int
import gleam/list
import gleam/string
import owned_test
import plan_error_samples.{type Sample, Sample}
import simplifile

/// The names of the variants of `PlanError`, read from the module that declares it.
fn declared_variants() -> List(String) {
  let path = "src/genesis_prime/game/spell_plan.gleam"
  let assert Ok(text) = simplifile.read(path)
    as "the plan's source is in the repository"
  let module = syntax.parse(SourceFile(path:, text:))
  let assert Ok(declared) =
    list.find(module.custom_types, fn(definition) {
      definition.definition.name == "PlanError"
    })
    as "spell_plan declares PlanError"
  list.map(declared.definition.variants, fn(variant: glance.Variant) {
    variant.name
  })
}

/// Checks a basis against the fact file: a question's record holds it, an unexplained value's
/// record exists. `without_a_record` is the one question the file holds no record for.
fn assert_basis_recorded(
  basis basis: Basis,
  label label: String,
  without_a_record without_a_record: String,
) -> Nil {
  case basis {
    OpenQuestion(question:) if question.fact == without_a_record -> {
      assert !coverage_support.has_record(
        facts: fact_file.records(),
        key: question.fact,
      )
        as {
          label
          <> ": the fact file holds no record of this type; the row is removed when one is written"
        }
    }
    OpenQuestion(question:) ->
      coverage_support.assert_question_recorded(question:, label:)
    Unexplained(fact:) -> {
      assert coverage_support.has_record(facts: fact_file.records(), key: fact)
        as { label <> ": the fact file holds no record " <> fact }
    }
    spell_plan.Unbuilt | spell_plan.Structure -> Nil
  }
}

pub fn every_plan_error_has_the_outcome_it_had_and_a_basis_whose_question_is_in_its_record_test() -> Nil {
  use <- owned_test.run(10_000)
  assert !prerequisite.is_read(
    type_id: plan_error_samples.undecoded_prerequisite_with_a_record,
  )
    as "type 102 is undecoded, so a gate on it is refused"
  assert !prerequisite.is_read(
    type_id: plan_error_samples.undecoded_prerequisite_without_a_record,
  )
    as "type 56 is undecoded, so a gate on it is refused"
  let without_a_record =
    "Prerequisite.prerequisiteTypeId."
    <> int.to_string(plan_error_samples.undecoded_prerequisite_without_a_record)
  let assert Ok(sample_source) =
    simplifile.read("test/plan_error_samples.gleam")
    as "the samples' source is in the repository"
  list.each(declared_variants(), fn(variant) {
    assert string.contains(sample_source, "spell_plan." <> variant <> "(")
      as { "the samples hold a row for the variant " <> variant }
  })
  list.each(plan_error_samples.samples(), fn(sample: Sample) {
    let Sample(error:, leaves_out:, basis:) = sample
    let label = spell_plan.describe(error:)
    let refusal = spell_plan.refusal_of(error:)
    assert refusal.outcome
      == case leaves_out {
        True -> LeavesOut
        False -> FailsLoad
      }
      as { label <> ": the outcome it had" }
    assert refusal.basis == basis
      as { label <> ": the basis the sample states" }
    assert_basis_recorded(basis: refusal.basis, label:, without_a_record:)
  })
}
