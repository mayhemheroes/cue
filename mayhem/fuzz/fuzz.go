// Package cuefuzz holds the Mayhem fuzz harness for the CUE parser.
//
// Legacy go-fuzz signature (func Fuzz([]byte) int) so go114-fuzz-build can turn
// it into a libFuzzer archive. Same code path as the original fork harness
// (parser.ParseFile) — target name `cue-parser-fuzz` is preserved.
package cuefuzz

import "cuelang.org/go/cue/parser"

func Fuzz(data []byte) int {
	_, _ = parser.ParseFile("fuzz.cue", data)
	return 0
}
