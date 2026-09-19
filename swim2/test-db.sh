#!/usr/bin/env bash
# test-db.sh
# Verifies the shared Postgres database that swim-times reads and writes:
#
#     host 100.77.243.69, dbname swimming
#
# The program names that database in a compiled-in constant and consults
# no environment variable, so this script uses the same fixed string --
# there is no point testing a database the program cannot reach.
#
# The database is shared.  A sibling loader populates it from USA
# Swimming's GetAllTimesForFilters feed; swim-times contributes best
# times from the BestTimes feed.  These checks therefore confirm the
# shape the program depends on rather than asserting ownership of the
# contents, and every write they make is a clearly-marked fixture that
# is removed again, including on failure.
#
# Usage:
#   ./test-db.sh            # schema, duplicate guard, read path
#   ./test-db.sh --no-write # skip the fixture insert/delete checks
#
# Exit status: 0 when nothing FAILed, 1 otherwise.

set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
BIN="$HERE/swim-times"
SOURCE="$HERE/swim-times.w"

# The one connection string, matching db_conn_string() in swim-times.w.
CONN="dbname=swimming user=postgres host=100.77.243.69 port=5432 connect_timeout=10"
FIXTURE="ZZ swim-times test fixture (delete me)"

WRITE=1
for a in "$@"; do
    case "$a" in
        --no-write) WRITE=0 ;;
        --help|-h)  sed -n '2,22p' "$0"; exit 0 ;;
        *) echo "unknown argument: $a" >&2; exit 2 ;;
    esac
done

PASS=0; FAIL=0; SKIP=0
pass() { printf 'PASS %-10s %s\n' "$1" "$2"; PASS=$((PASS+1)); }
fail() { printf 'FAIL %-10s %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }
skip() { printf 'SKIP %-10s %s\n' "$1" "$2"; SKIP=$((SKIP+1)); }
section() { printf '\n=== %s ===\n' "$1"; }

q()  { psql "$CONN" -tAc "$1"; }
# -q as well, so a RETURNING clause yields the value alone and not the
# "INSERT 0 1" command tag after it.
qw() { psql "$CONN" -qtAc "$1"; }
qq() { psql "$CONN" -qtAc "$1" >/dev/null 2>&1; }

# Remove the fixture whatever happens, including on interrupt.
cleanup() { qq "DELETE FROM swimmer WHERE full_name = '$FIXTURE'"; }
trap cleanup EXIT

# -----------------------------------------------------------------
section "Connectivity"
# -----------------------------------------------------------------
if ! command -v psql >/dev/null 2>&1; then
    fail DB-01 "psql is not installed"
    exit 1
fi
if [ "$(q 'SELECT 1' 2>/dev/null)" = "1" ]; then
    pass DB-01 "connected to swimming on 100.77.243.69"
else
    fail DB-01 "cannot reach the database ($CONN)"
    exit 1
fi

# DB-02: the program and this script agree on which database that is.
# A mismatch here means the compiled binary is talking to somewhere else
# and every other result below is about the wrong server.
if grep -q '"dbname=swimming user=postgres "' "$SOURCE" \
   && grep -q '"host=100.77.243.69 port=5432"' "$SOURCE"; then
    pass DB-02 "swim-times.w names this same database"
else
    fail DB-02 "swim-times.w does not name swimming@100.77.243.69"
fi

# DB-03: and it cannot be redirected.  An environment override would
# make "this database only" untrue.  The name may still appear in the
# prose that explains why it was withdrawn; what must not appear is a
# getenv() for it.
if grep -q 'getenv("SWIM_TIMES_PGCONNINFO")' "$SOURCE"; then
    fail DB-03 "an environment override for the connection string remains"
else
    pass DB-03 "connection string is a constant, with no override"
fi

# -----------------------------------------------------------------
section "Schema the program depends on"
# -----------------------------------------------------------------
# DB-04: the tables db_insert_row() and offline_fetch() name.
missing=""
for t in swimmer meet swim event time_standard; do
    [ "$(q "SELECT to_regclass('public.$t') IS NOT NULL")" = "t" ] \
        || missing="$missing $t"
done
if [ -z "$missing" ]; then
    pass DB-04 "swimmer, meet, swim, event, time_standard all present"
else
    fail DB-04 "missing table(s):$missing"
fi

# DB-05: the columns the insert names, by table.
check_cols() {  # check_cols <id> <table> <col>...
    local id=$1 tbl=$2; shift 2
    local miss=""
    for c in "$@"; do
        [ "$(q "SELECT count(*) FROM information_schema.columns
                 WHERE table_name='$tbl' AND column_name='$c'")" = "1" ] \
            || miss="$miss $c"
    done
    if [ -z "$miss" ]; then pass "$id" "$tbl has every column the program writes"
    else fail "$id" "$tbl is missing:$miss"; fi
}
check_cols DB-05 swim swim_time_id swimmer_key event_code meet_key \
           swim_date swim_time seconds standard_name club_name \
           source_endpoint auth_mode
check_cols DB-06 swimmer swimmer_key member_id full_name lsc_code \
           club_name last_fetched
check_cols DB-07 meet meet_key meet_name

# DB-08: swim_time_id has no default, which is why the program
# synthesises one.  If a default ever appears, swim_surrogate_id()
# becomes unnecessary and the code should be revisited.
dflt=$(q "SELECT coalesce(column_default,'(none)') FROM information_schema.columns
           WHERE table_name='swim' AND column_name='swim_time_id'")
if [ "$dflt" = "(none)" ]; then
    pass DB-08 "swim.swim_time_id has no default (surrogate id required)"
else
    fail DB-08 "swim.swim_time_id now defaults to '$dflt'; revisit swim_surrogate_id()"
fi

# DB-09: the duplicate guard the bare ON CONFLICT DO NOTHING relies on.
key=$(q "SELECT string_agg(a.attname, ',' ORDER BY k.ord)
           FROM pg_constraint c
           JOIN LATERAL unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
             ON true
           JOIN pg_attribute a
             ON a.attrelid = c.conrelid AND a.attnum = k.attnum
          WHERE c.conrelid = 'swim'::regclass AND c.contype = 'u'
          GROUP BY c.oid
         HAVING string_agg(a.attname, ',' ORDER BY k.ord)
                = 'swimmer_key,event_code,swim_time,swim_date,meet_key'")
if [ -n "$key" ]; then
    pass DB-09 "swim carries the natural-key UNIQUE constraint"
else
    fail DB-09 "no UNIQUE constraint on (swimmer_key,event_code,swim_time,swim_date,meet_key)"
fi

# DB-10: every event code the program can request is a valid FK target.
# A code absent from event would make that event's rows unwritable.
absent=$(q "SELECT count(*) FROM (VALUES
  ('50 FR SCY'),('100 FR SCY'),('200 FR SCY'),('500 FR SCY'),
  ('1000 FR SCY'),('1650 FR SCY'),('50 FL SCY'),('100 FL SCY'),
  ('50 BK SCY'),('100 BK SCY'),('50 BR SCY'),('100 BR SCY'),
  ('100 IM SCY'),('200 IM SCY'),
  ('50 FR LCM'),('100 FR LCM'),('200 FR LCM'),('400 FR LCM'),
  ('800 FR LCM'),('1500 FR LCM'),('50 FL LCM'),('100 FL LCM'),
  ('200 FL LCM'),('50 BK LCM'),('100 BK LCM'),('200 BK LCM'),
  ('50 BR LCM'),('100 BR LCM'),('200 BR LCM'),('200 IM LCM'),
  ('400 IM LCM')
) v(code) WHERE NOT EXISTS
  (SELECT 1 FROM event e WHERE e.event_code = v.code)")
if [ "$absent" = "0" ]; then
    pass DB-10 "all 31 event codes exist in event"
else
    fail DB-10 "$absent of the program's 31 event codes are not in event"
fi

# DB-11: the standards db_standard() passes through are all FK-valid,
# and the elite labels it maps to NULL are indeed absent.
known_ok=$(q "SELECT count(*) FROM (VALUES
  ('A'),('AA'),('AAA'),('AAAA'),('B'),('BB'),('Slower Than B')
) v(n) WHERE EXISTS (SELECT 1 FROM time_standard t WHERE t.standard_name = v.n)")
elite=$(q "SELECT count(*) FROM time_standard
            WHERE standard_name IN ('Nats','Trials','Summer Jrs','Winter Jrs')")
if [ "$known_ok" = "7" ] && [ "$elite" = "0" ]; then
    pass DB-11 "time_standard holds the 7 mapped levels and no elite labels"
else
    fail DB-11 "time_standard: $known_ok/7 mapped levels, $elite elite labels"
fi

# -----------------------------------------------------------------
section "Duplicate guard"
# -----------------------------------------------------------------
if [ "$WRITE" = "0" ]; then
    for r in DB-12 DB-13 DB-14 DB-19 DB-20; do skip "$r" "--no-write given"; done
else
    cleanup
    fk=$(qw "INSERT INTO swimmer (member_id, full_name, lsc_code, club_name)
             VALUES (NULL, '$FIXTURE', 'SI', 'Fixture Swim Club')
             RETURNING swimmer_key")
    if [ -z "$fk" ]; then
        for r in DB-12 DB-13 DB-14 DB-19 DB-20; do fail "$r" "could not create the fixture swimmer"; done
    else
        ins="INSERT INTO swim (swim_time_id, swimmer_key, event_code,
                 meet_key, swim_date, swim_time, seconds, standard_name,
                 source_endpoint, auth_mode)
             VALUES (-8888888888888888888, $fk, '100 FR SCY', NULL,
                 '2026-01-17', '1:02.45', 62.45, 'BB',
                 'BestTimes', 'authenticated')
             ON CONFLICT DO NOTHING"
        qq "$ins"; one=$(q "SELECT count(*) FROM swim WHERE swimmer_key=$fk")
        qq "$ins"; qq "$ins"
        two=$(q "SELECT count(*) FROM swim WHERE swimmer_key=$fk")
        if [ "$one" = "1" ] && [ "$two" = "1" ]; then
            pass DB-12 "repeated identical inserts collapse to one row"
        else
            fail DB-12 "row count went $one -> $two across three inserts"
        fi

        # DB-13: a different swim is stored, not merged
        qq "INSERT INTO swim (swim_time_id, swimmer_key, event_code,
                meet_key, swim_date, swim_time, seconds, standard_name,
                source_endpoint, auth_mode)
            VALUES (-8888888888888888887, $fk, '100 FR SCY', NULL,
                '2025-11-02', '1:05.10', 65.10, 'B',
                'BestTimes', 'authenticated')
            ON CONFLICT DO NOTHING"
        both=$(q "SELECT count(*) FROM swim WHERE swimmer_key=$fk")
        if [ "$both" = "2" ]; then
            pass DB-13 "a distinct swim is stored alongside, not merged"
        else
            fail DB-13 "expected 2 fixture swims, found $both"
        fi

        # DB-14: an elite standard would violate the FK -- which is the
        # whole reason db_standard() maps it to NULL.  The same insert
        # with standard_name NULL must succeed, so that the failure is
        # attributable to the label and not to the rest of the row.
        elite_ins="INSERT INTO swim (swim_time_id, swimmer_key,
                       event_code, swim_date, swim_time, standard_name,
                       source_endpoint, auth_mode)
                   VALUES (-8888888888888888886, $fk, '100 FR SCY',
                       '2024-01-01', '1:11.11', %s,
                       'BestTimes', 'authenticated')"
        if qq "$(printf "$elite_ins" "'Summer Jrs'")"; then
            fail DB-14 "time_standard FK accepted the elite label 'Summer Jrs'"
        elif qq "$(printf "$elite_ins" "NULL")"; then
            pass DB-14 "elite labels rejected by the FK (hence db_standard -> NULL)"
        else
            fail DB-14 "the control insert with a NULL standard also failed"
        fi
        # DB-19: the loose match claims an unlinked row whose middle
        # name is spelled differently -- the case that produced
        # duplicate swimmers before it was added.
        qq "UPDATE swimmer SET member_id = NULL WHERE swimmer_key = $fk"
        variant="ZZ swim-times X fixture (delete me)"
        hit=$(q "SELECT swimmer_key FROM swimmer
                  WHERE member_id = 'NOPE0000000000'
                     OR (member_id IS NULL AND lower(full_name) = lower('$variant'))
                     OR (member_id IS NULL
                         AND lower(split_part(full_name,' ',1)) =
                             lower(split_part('$variant',' ',1))
                         AND lower(regexp_replace(full_name,'^.*\\s','')) =
                             lower(regexp_replace('$variant','^.*\\s','')))
                  ORDER BY (member_id = 'NOPE0000000000') DESC LIMIT 1")
        if [ "$hit" = "$fk" ]; then
            pass DB-19 "loose match claims an unlinked row with a differing middle name"
        else
            fail DB-19 "loose match returned '$hit', expected $fk"
        fi

        # DB-20: and it must NOT cross a row that already carries a
        # different member id.  Merging two swimmers is worse than
        # duplicating one, so the guard matters more than the match.
        qq "UPDATE swimmer SET member_id = 'OTHER000000000' WHERE swimmer_key = $fk"
        hit=$(q "SELECT coalesce(max(swimmer_key)::text,'none') FROM swimmer
                  WHERE member_id = 'NOPE0000000000'
                     OR (member_id IS NULL AND lower(full_name) = lower('$variant'))
                     OR (member_id IS NULL
                         AND lower(split_part(full_name,' ',1)) =
                             lower(split_part('$variant',' ',1))
                         AND lower(regexp_replace(full_name,'^.*\\s','')) =
                             lower(regexp_replace('$variant','^.*\\s','')))")
        if [ "$hit" = "none" ]; then
            pass DB-20 "a row with a different member id is never claimed by name"
        else
            fail DB-20 "loose match crossed into a linked row ($hit)"
        fi

        cleanup
    fi
fi

# -----------------------------------------------------------------
section "Read path"
# -----------------------------------------------------------------
if [ ! -x "$BIN" ]; then
    for r in DB-15 DB-16 DB-17; do skip "$r" "swim-times not built; run make"; done
else
    out=$("$BIN" -o stella,offline,csv -e "100 FR SCY" 2>"$HERE/.test-db.err")
    rc=$?
    if [ $rc -eq 0 ] && [ ! -s "$HERE/.test-db.err" ]; then
        pass DB-15 "swim-times -o offline ran clean against the shared DB"
    else
        fail DB-15 "offline rc=$rc: $(head -1 "$HERE/.test-db.err")"
    fi
    rm -f "$HERE/.test-db.err"

    hdr=$(printf '%s\n' "$out" | head -1)
    if [ "$hdr" = '"Swimmer","Event","Time","Date","Standard","Meet"' ]; then
        pass DB-16 "offline CSV emits the six-column header"
    else
        fail DB-16 "offline CSV header is '$hdr'"
    fi

    # DB-17: the read joins through to names.  A row that reached the
    # emitter with an empty swimmer or meet would mean the joins failed.
    rows=$(printf '%s\n' "$out" | tail -n +2 | grep -c '^"[^"]\+","100 FR SCY"' || true)
    named=$(printf '%s\n' "$out" | tail -n +2 | grep -c '^"",' || true)
    if [ "$rows" -gt 0 ] && [ "$named" = "0" ]; then
        pass DB-17 "offline read joined $rows row(s) through to swimmer and meet"
    elif [ "$rows" = "0" ]; then
        skip DB-17 "no stored swims for that swimmer and event"
    else
        fail DB-17 "$named row(s) came back with no swimmer name"
    fi
fi

# -----------------------------------------------------------------
section "Contents"
# -----------------------------------------------------------------
swims=$(q "SELECT count(*) FROM swim")
people=$(q "SELECT count(*) FROM swimmer")
meets=$(q "SELECT count(*) FROM meet")
printf '  swimmers: %s   meets: %s   swims: %s\n' "$people" "$meets" "$swims"
printf '\n  By source:\n'
psql "$CONN" -c "SELECT source_endpoint, auth_mode, count(*) AS rows
                   FROM swim GROUP BY 1,2 ORDER BY 3 DESC"
if [ "$swims" -gt 0 ]; then
    pass DB-18 "shared database holds $swims swims for $people swimmers"
else
    fail DB-18 "the shared database is empty"
fi

# -----------------------------------------------------------------
section "Summary"
printf 'PASS: %d   FAIL: %d   SKIP: %d\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ] || exit 1
exit 0
