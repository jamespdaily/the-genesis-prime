//// The heap ceiling of a connection and the connection cap. The expected
//// values come from the heap-ceiling rule of the prototype's measurement
//// (four times the measured peak, rounded up to a power of two words), which gave 131,072 words for a peak of 32,317 and 8,388,608
//// for a peak of 1,103,592, and from the cap's own rule: the heap ceilings of
//// all connections together stay under 1 GB.

import genesis_prime/connection/capacity
import owned_test

pub fn the_ceiling_is_four_times_the_peak_as_a_power_of_two_test() -> Nil {
  use <- owned_test.run(5000)
  assert capacity.heap_ceiling_for_peak(peak_words: 32_317) == 131_072
    as "the sender's peak of 32,317 words gave a ceiling of 131,072 words (2^17)"
  assert capacity.heap_ceiling_for_peak(peak_words: 1_103_592) == 8_388_608
    as "the map process's peak of 1,103,592 words gave a ceiling of 8,388,608 words (2^23)"
  assert capacity.heap_ceiling_for_peak(peak_words: 1024) == 4096
    as "four times 1,024 is exactly a power of two, 4,096"
  assert capacity.heap_ceiling_for_peak(peak_words: 1025) == 8192
    as "four times 1,025 is 4,100, which rounds up to 8,192"
  assert capacity.heap_ceiling_for_peak(peak_words: 1) == 4
    as "a peak of one word gives four"
}

pub fn the_cap_is_the_most_connections_whose_ceilings_stay_under_one_gigabyte_test() -> Nil {
  use <- owned_test.run(5000)
  let ceilings = [4096, 131_072, 1_048_576]
  assert keep_breaking_the_rule(ceilings) == []
    as "for each ceiling, cap times the ceiling in bytes is under 1 GB and one more connection is not"
}

fn keep_breaking_the_rule(ceilings: List(Int)) -> List(Int) {
  case ceilings {
    [] -> []
    [ceiling, ..rest] -> {
      let bytes = ceiling * 8
      let cap = capacity.connection_cap_for(ceiling_words: ceiling)
      case
        cap * bytes < capacity.memory_limit_bytes
        && { cap + 1 } * bytes >= capacity.memory_limit_bytes
      {
        True -> keep_breaking_the_rule(rest)
        False -> [ceiling, ..keep_breaking_the_rule(rest)]
      }
    }
  }
}

pub fn the_cap_for_a_known_ceiling_is_a_known_number_test() -> Nil {
  use <- owned_test.run(5000)
  assert capacity.connection_cap_for(ceiling_words: 131_072) == 953
    as "131,072 words are 1,048,576 bytes; 953 of them are 999,292,928 bytes, under 1,000,000,000, and 954 are 1,000,341,504, over"
}

pub fn the_servers_ceiling_and_cap_come_from_its_measured_peak_test() -> Nil {
  use <- owned_test.run(5000)
  assert capacity.heap_ceiling_words()
    == capacity.heap_ceiling_for_peak(peak_words: capacity.peak_heap_words())
    as "the ceiling is the rule applied to the measured peak"
  assert capacity.connection_cap()
    == capacity.connection_cap_for(ceiling_words: capacity.heap_ceiling_words())
    as "the cap is the rule applied to the ceiling"
  assert capacity.connection_cap() * capacity.heap_ceiling_words() * 8
    < capacity.memory_limit_bytes
    as "the server's cap times its ceiling is under 1 GB"
}
