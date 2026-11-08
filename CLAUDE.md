# the-genesis-prime
A server for WildStar that the original client connects to and plays on. Gleam on the BEAM (Erlang/OTP); Postgres for saved data.

## Terms
- **Step:** one sub-issue, one branch, one pull request, with a fixed test list. A step changes one client flow or one process design; a larger one is split before its test list is posted.
- **Test list:** a step's planned tests on its issue, behaviours and failure paths, each naming its evidence.
- **Evidence:** the client's code and tables, then recordings; a retail record or Jim's world database only where the client lacks the data.
- **Rule:** a pure function: state and input in, new state and effects (actions to carry out) out. Every game and connection decision is a rule.
- **Shell:** the process that carries out its rule's effects in order and turns all it sees into that rule's inputs; it decides nothing.
- **Full check:** `./check`: the setup check, format, warnings as errors, glinter, generated code matching the schema, migrations, squirrel, the tests and the fact checker. CI runs it without the client's parts.
- **Coverage measure:** what the client's tables require, against what the server handles.

## Authority
- The client and its data files are the only authority on what the server must do; every protocol or game-rule fact in code points to its evidence.
- The client's tables set the scope; each run of the coverage measure is posted on its issue.
- Never copy another WildStar server's code, text or structure; none of it is evidence. Jim's earlier server, the-eldan-experiment, may be read to find questions, client addresses and sources, and to compare designs. A fact it points to is accepted only once the client's own code or data confirms it. A design it shows is chosen only on this project's own evidence. NexusForever is never read.
- Retail records (Jabbithole, Dulfy, wikis) and Jim's world database (wildstar-knowledge world-data) count only for data the client lacks, such as spawns, vendor stock and loot, and each such value is marked with its source. The world database is data to read, never code or structure to copy.
- Read a problem's rows and evidence before calling it a bug, a decision or a fix; a search that found nothing settles nothing.

## Every change
- Handle errors you can act on; let anything else crash the process, and its supervisor rebuilds it from storage.
- Decode client bytes at the connection into typed values. Bytes the client's own reader would refuse end the connection; a whole frame the server does not know yet is logged as unhandled, and the connection goes on.
- Refuse any value the client sends that its own code or tables would not allow.
- Game tables load once at start into named records; a missing row fails the load.
- Every packet layout lives in one schema with its evidence. The generated codec states each field's size and byte order and is never edited by hand; the bit stream's field kinds and the generator are property-tested, and each message with a client vector is checked against it.
- A bug fix starts with a test that fails because of the bug.
- CI's full check passes on the commit handed back for review: a builder runs single tests and `./check fast` locally, and pushes to a draft pull request so CI runs. The coordinator runs `./check` locally once, on the commit it merges, for the parts that need the client. Files are staged by name.
- No shortcut makes a check pass: no stub or hard-coded value in place of the client's behaviour, no test skipped or loosened without its reason in the test, no swallowed error. A gap is stated where it is enforced, names the open issue that will close it, and is reported as missing or a question.
- A requirement or fact lives in the code, test, config or check that enforces it. No design documents or decision records: the issue keeps the reasoning, and a choice becomes one line in its place. Tools that gate a merge (the check script, the setup check, the table extractor) have tests that CI runs; other tools and guidance are checked by real use.
- A branch is `jimd/<issue>-<topic>`; each commit names its issue and says why.
- A lesson becomes a test, a shared function or a permission first; a written rule only for a recurring judgement, and it names the failure it fixes, seen in real work. A new rule replaces an old one where it can. A change to this file, a skill or an agent lands in its own pull request once Jim approves it; an approved change that waits for a step is written on that step's issue.

## Steps
The coordinator runs each step by the `running-a-step` skill. Jim decides only when expected game behaviour changes, an acceptance condition weakens, the evidence cannot settle a question, or authority widens: ask those as one batch of yes-or-no questions, each with a recommendation.
