package parser

import "testing"

func FuzzParseFile(f *testing.F) {
	f.Add([]byte("{}"))
	f.Fuzz(func(t *testing.T, data []byte) {
		_, _ = ParseFile("fuzz.cue", data)
	})
}
