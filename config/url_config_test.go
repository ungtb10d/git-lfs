package config

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestURLConfig(t *testing.T) {
	u := NewURLConfig(EnvironmentOf(MapFetcher(map[string][]string{
		"http.key":                                []string{"root", "root-2"},
		"http.https://host.com.key":               []string{"host", "host-2"},
		"http.https://user@host.com/a.key":        []string{"user-a", "user-b"},
		"http.https://user@host.com.key":          []string{"user", "user-2"},
		"http.https://host.com/a.key":             []string{"host-a", "host-b"},
		"http.https://host.com:8080.key":          []string{"port", "port-2"},
		"http.https://host.com/repo.git.key":      []string{".git"},
		"http.https://host.com/repo.key":          []string{"no .git"},
		"http.https://host.com/repo2.key":         []string{"no .git"},
		"http.http://host.com/repo.key":           []string{"http"},
		"http.https://host.com:443/repo3.git.key": []string{"port"},
		"http.ssh://host.com:22/repo3.git.key":    []string{"ssh-port"},
		"http.https://host.*/a.key":               []string{"wild"},
		"httpXhttps://host.*/aXkey":               []string{"invalid"},
	})))

	getOne := map[string]string{
		"https://root.com/a/b/c":                      "root-2",
		"https://host.com/":                           "host-2",
		"https://host.com/a/b/c":                      "host-b",
		"https://user:pass@host.com/a/b/c":            "user-b",
		"https://user:pass@host.com/z/b/c":            "user-2",
		"https://host.com:8080/a":                     "port-2",
		"https://host.com/repo.git/info/lfs":          ".git",
		"https://host.com/repo.git/info":              ".git",
		"https://host.com/repo.git":                   ".git",
		"https://host.com/repo":                       "no .git",
		"https://host.com/repo2.git/info/lfs/foo/bar": "no .git",
		"https://host.com/repo2.git/info/lfs":         "no .git",
		"https://host.com:443/repo2.git/info/lfs":     "no .git",
		"https://host.com/repo2.git/info":             "host-2", // doesn't match /.git/info/lfs\Z/
		"https://host.com/repo2.git":                  "host-2", // ditto
		"https://host.com/repo3.git/info/lfs":         "port",
		"ssh://host.com/repo3.git/info/lfs":           "ssh-port",
		"https://host.com/repo2":                      "no .git",
		"http://host.com/repo":                        "http",
		"http://host.com:80/repo":                     "http",
		"https://host.wild/a/b/c":                     "wild",
	}

	for rawurl, expected := range getOne {
		value, _ := u.Get("http", rawurl, "key")
		assert.Equal(t, expected, value, "get one: "+rawurl)
	}

	value, _ := u.Get("http", "https://host.wild/a/b/c", "k")
	assert.Equal(t, value, "")
	value, _ = u.Get("ttp", "https://host.wild/a/b/c", "key")
	assert.Equal(t, value, "")

	getAll := map[string][]string{
		"https://root.com/a/b/c":           []string{"root", "root-2"},
		"https://host.com/":                []string{"host", "host-2"},
		"https://host.com/a/b/c":           []string{"host-a", "host-b"},
		"https://user:pass@host.com/a/b/c": []string{"user-a", "user-b"},
		"https://user:pass@host.com/z/b/c": []string{"user", "user-2"},
		"https://host.com:8080/a":          []string{"port", "port-2"},
	}

	for rawurl, expected := range getAll {
		values := u.GetAll("http", rawurl, "key")
		assert.Equal(t, expected, values, "get all: "+rawurl)
	}
}
