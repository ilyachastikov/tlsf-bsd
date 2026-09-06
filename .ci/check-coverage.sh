#!/usr/bin/env bash

# Line coverage floor for the core allocator.
#
# The suite is what stands between this allocator and silent heap corruption,
# and nothing used to measure how much of it the suite reached. The first run
# of this script found eight unreached lines, every one of them a rejection
# path that no randomized test can stumble into.
#
# The three correctness binaries run below all link the same build/tlsf.o and
# gcov accumulates counts across runs, so the figure is their union rather than
# whatever one of them happens to touch. bench and wcet are left out: they
# exercise paths the three already cover, and they cost minutes.
#
# Assertions are compiled out for the measurement, heap checking left on. With
# TLSF_ENABLE_ASSERT the ASSERT() lines inside the always-inline helpers carry
# the call to __assert_fail, a basic block a passing run must never enter, so
# gcc reports eight of them as unreached and the figure punishes the suite for
# not failing. gcc and clang also disagree about which line to charge them to,
# which made a floor calibrated on one toolchain fail on the other. Removing
# them leaves every remaining unreached line a real gap.
#
# The floor is a ratchet. Raise it when coverage rises; do not lower it to make
# a change fit, because that is exactly the change worth looking at. What stays
# unreached is the configured-ceiling rejections, in arena_grow(), in the append
# path and in tlsf_pool_init(), which only a reduced TLSF_MAX_POOL_BITS can
# reach and the configuration jobs in CI do cover, plus the guard in
# tlsf_get_stats() against an allocator that claims bytes with no arena, which
# no legal call sequence produces. How many lines gcov charges those to depends
# on the toolchain: one on gcc, four on clang.
set -e -u -o pipefail

FLOOR="${COVERAGE_FLOOR:-99}"
GCOV="${GCOV:-gcov}"

make clean >/dev/null
CFLAGS="--coverage" LDFLAGS="--coverage" \
	make all TLSF_DEBUG_FLAGS=-DTLSF_ENABLE_CHECK

# Pinned so that a drop here can be re-run. tests/test.c otherwise seeds
# itself from time(0), which leaves a failing measurement impossible to
# reproduce. build/fuzz already defaults to a fixed seed.
#
# This does not make the figure deterministic by itself, and it was measured
# rather than assumed: with the seed pinned, six consecutive runs still split
# 208/209 on the branch count. The one that moves is an arm of the compound
# argument guard in tlsf_aalloc(), which the thread stress test reaches
# incidentally a handful of times in some ninety thousand calls, or not at
# all, depending on scheduling. The floor below carries headroom for it.
TLSF_TEST_SEED=1 ./build/test >/dev/null
./build/test_thread >/dev/null
./build/fuzz >/dev/null

report="$(${GCOV} -b -c -o build src/tlsf.c)"
printf '%s\n' "$report"

pct="$(printf '%s\n' "$report" |
	awk -F'[:%]' '/Lines executed:/ { print $2; exit }')"
if [ -z "$pct" ]; then
	echo "check-coverage: no line-coverage figure from '$GCOV'" >&2
	exit 1
fi

echo "unreached lines in src/tlsf.c:"
grep '#####' tlsf.c.gcov | sed 's/^/  /' || echo "  none"

awk -v got="$pct" -v floor="$FLOOR" 'BEGIN {
	msg = sprintf("check-coverage: %s%% of lines in src/tlsf.c, floor %s%%",
	              got, floor)
	if (got + 0 < floor + 0) {
		print msg > "/dev/stderr"
		exit 1
	}
	print msg
}'

# Branch coverage over the same run, with the CHECK() arms taken out.
#
# tlsf_check() and its helpers are one CHECK() after another, and the failing
# arm of each is the corruption report a passing suite must never take. Those
# arms are unreachable in the same way as the ASSERT lines compiled out above,
# so counting them caps the figure at a number no test can lift.
#
# Counts, not the percentages gcov prints without -c: a branch taken once in
# hundreds of millions rounds to "taken 0%" and would read as never taken.
#
# How far the floor sits under the measured figure was settled by measuring
# both toolchains, not by taste. gcc and clang disagree about how a
# short-circuit operator decomposes into branches, the same divergence the
# unreached-line note above records, and the gap is in the denominator rather
# than the ratio: the same suite reports 94.48% of 290 reachable branches
# under the gcc this job runs, and 94.14% of 222 under clang. On top of that
# the figure moves by one branch between runs, for the scheduling reason
# recorded at the test invocation, worth 0.34 points on gcc and 0.45 on clang.
#
# 93 clears both toolchains with their jitter and still fails on the loss of a
# few branches. A floor of 90 would have hidden thirteen of them on gcc, which
# is the class of regression this gate exists to catch.
BRANCH_FLOOR="${BRANCH_FLOOR:-93}"

awk -v floor="$BRANCH_FLOOR" '
	/^ *[^:]*: *[0-9]+:/ { src = $0 }
	/^branch / {
		if (src ~ /CHECK\(/)
			next
		total++
		if ($4 + 0 > 0)
			next
		missed++
		line = src
		sub(/^[^:]*: */, "", line)
		if (!(line in seen)) {
			seen[line] = 1
			untaken[++u] = line
		}
	}
	END {
		if (!total) {
			print "check-coverage: no branch records in tlsf.c.gcov" \
				> "/dev/stderr"
			exit 1
		}
		print "reachable branches never taken in src/tlsf.c:"
		for (i = 1; i <= u; i++)
			print "  " untaken[i]
		if (!u)
			print "  none"
		got = (total - missed) * 100 / total
		msg = sprintf("check-coverage: %.2f%% of %d reachable branches in " \
		              "src/tlsf.c (%d taken), floor %s%%",
		              got, total, total - missed, floor)
		if (got < floor + 0) {
			print msg > "/dev/stderr"
			exit 1
		}
		print msg
	}' tlsf.c.gcov
