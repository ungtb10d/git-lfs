#!/usr/bin/env bash

. "$(dirname "$0")/testlib.sh"

begin_test "status"
(
  set -e

  mkdir repo-1
  cd repo-1
  git init
  git lfs track "*.dat"

  file_1="some data"
  file_1_oid="$(calc_oid "$file_1")"
  file_1_oid_short="$(echo "$file_1_oid" | head -c 7)"
  printf "%s" "$file_1" > file1.dat
  git add file1.dat
  git commit -m "file1.dat"

  file_1_new="other data"
  file_1_new_oid="$(calc_oid "$file_1_new")"
  file_1_new_oid_short="$(echo "$file_1_new_oid" | head -c 7)"
  printf "%s" "$file_1_new" > file1.dat

  file_2="file2 data"
  file_2_oid="$(calc_oid "$file_2")"
  file_2_oid_short="$(echo "$file_2_oid" | head -c 7)"
  printf "%s" "$file_2" > file2.dat
  git add file2.dat

  file_3="file3 data"
  file_3_oid="$(calc_oid "$file_3")"
  file_3_oid_short="$(echo "$file_3_oid" | head -c 7)"
  printf "%s" "$file_3" > file3.dat
  git add file3.dat

  file_3_new="file3 other data"
  file_3_new_oid="$(calc_oid "$file_3_new")"
  file_3_new_oid_short="$(echo "$file_3_new_oid" | head -c 7)"
  printf "%s" "$file_3_new" > file3.dat

  expected="On branch main

Objects to be committed:

	file2.dat (LFS: $file_2_oid_short)
	file3.dat (LFS: $file_3_oid_short)

Objects not staged for commit:

	file1.dat (LFS: $file_1_oid_short -> File: $file_1_new_oid_short)
	file3.dat (File: $file_3_new_oid_short)"

  [ "$expected" = "$(git lfs status)" ]
)
end_test

begin_test "status --porcelain"
(
  set -e

  mkdir repo-2
  cd repo-2
  git init
  git lfs track "*.dat"
  echo "some data" > file1.dat
  git add file1.dat
  git commit -m "file1.dat"

  echo "other data" > file1.dat
  echo "file2 data" > file2.dat
  git add file2.dat

  echo "file3 data" > file3.dat
  git add file3.dat

  echo "file3 other data" > file3.dat

  expected=" M file1.dat
A  file3.dat
A  file2.dat"

  [ "$expected" = "$(git lfs status --porcelain)" ]
)
end_test

begin_test "status --json"
(
  set -e

  mkdir repo-3
  cd repo-3
  git init
  git lfs track "*.dat"
  echo "some data" > file1.dat
  git add file1.dat
  git commit -m "file1.dat"

  echo "other data" > file1.dat

  expected='{"files":{"file1.dat":{"status":"M"}}}'
  [ "$expected" = "$(git lfs status --json)" ]

  git add file1.dat
  git commit -m "file1.dat changed"
  git mv file1.dat file2.dat

  expected='{"files":{"file2.dat":{"status":"R","from":"file1.dat"}}}'
  [ "$expected" = "$(git lfs status --json)" ]

  git commit -m "file1.dat -> file2.dat"

  # Ensure status --json does not include non-lfs files
  echo hi > test1.txt
  git add test1.txt
  expected='{"files":{}}'
  [ "$expected" = "$(git lfs status --json)" ]
)
end_test

begin_test "status in a sub-directory"
(
  set -e

  reponame="status-sub-directory"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  printf "asdf" > file.dat
  mkdir -p dir
  git add .gitattributes file.dat
  git commit -m "initial commit"

  printf "ASDF" > file.dat

  expected="On branch main

Objects to be committed:


Objects not staged for commit:

	../file.dat (LFS: f0e4c2f -> File: 99b3bcf)"

	[ "$expected" = "$(cd dir && git lfs status)" ]
)
end_test

begin_test "status: outside git repository"
(
  set +e
  git lfs status 2>&1 > status.log
  res=$?

  set -e
  if [ "$res" = "0" ]; then
    echo "Passes because $GIT_LFS_TEST_DIR is unset."
    exit 0
  fi
  [ "$res" = "128" ]
  grep "Not in a Git repository" status.log
)
end_test

begin_test "status - before initial commit"
(
  set -e

  git init repo-initial
  cd repo-initial
  git lfs track "*.dat"

  # should not fail when nothing to display (ignore output, will be blank)
  git lfs status

  contents="some data"
  contents_oid="$(calc_oid "$contents")"
  contents_oid_short="$(echo "$contents_oid" | head -c 7)"

  printf "%s" "$contents" > file1.dat
  git add file1.dat

  expected="
Objects to be committed:

	file1.dat (LFS: $contents_oid_short)

Objects not staged for commit:"

  [ "$expected" = "$(git lfs status)" ]
)
end_test

begin_test "status shows multiple files with identical contents"
(
  set -e

  reponame="uniq-status"
  mkdir "$reponame"
  cd "$reponame"

  git init
  git lfs track "*.dat"

  contents="contents"
  printf "%s" "$contents" > a.dat
  printf "%s" "$contents" > b.dat

  git add --all .

  git lfs status | tee status.log

  [ "1" -eq "$(grep -c "a.dat" status.log)" ]
  [ "1" -eq "$(grep -c "b.dat" status.log)" ]
)
end_test

begin_test "status shows multiple copies of partially staged files"
(
  set -e

  reponame="status-partially-staged"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  contents_1="part 1"
  contents_1_oid="$(calc_oid "$contents_1")"
  contents_1_oid_short="$(echo "$contents_1_oid" | head -c 7)"
  printf "%s" "$contents_1" > a.dat

  # "$contents_1" changes are staged
  git add a.dat

  # "$contents_2" changes are unstaged
  contents_2="part 2"
  contents_2_oid="$(calc_oid "$contents_2")"
  contents_2_oid_short="$(echo "$contents_2_oid" | head -c 7)"
  printf "%s" "$contents_2" > a.dat

  expected="On branch main

Objects to be committed:

	a.dat (LFS: $contents_1_oid_short)

Objects not staged for commit:

	a.dat (File: $contents_2_oid_short)"
  actual="$(git lfs status)"

  diff -u <(echo "$expected") <(echo "$actual")
)
end_test

begin_test "status: LFS to LFS change"
(
  set -e

  reponame="status-lfs-to-lfs-change"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  contents="contents"
  contents_oid="$(calc_oid "$contents")"
  contents_oid_short="$(echo "$contents_oid" | head -c 7)"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "track *.dat files"

  printf "%s" "$contents" > a.dat
  git add a.dat
  git commit -m "add a.dat"

  contents_new="$contents +extra"
  contents_new_oid="$(calc_oid "$contents_new")"
  contents_new_oid_short="$(echo $contents_new_oid | head -c 7)"

  printf "%s" "$contents_new" > a.dat
  git add a.dat

  expected="On branch main

Objects to be committed:

	a.dat (LFS: $contents_oid_short -> LFS: $contents_new_oid_short)

Objects not staged for commit:"
  actual="$(git lfs status)"

  [ "$expected" = "$actual" ]
)
end_test

begin_test "status: Git to LFS change"
(
  set -e

  reponame="status-git-to-lfs-change"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  contents="contents"
  contents_oid="$(calc_oid "$contents")"
  contents_oid_short="$(echo "$contents_oid" | head -c 7)"

  printf "%s" "$contents" > a.dat
  git add a.dat
  git commit -m "add a.dat"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "track *.dat files"

  contents_new="$contents +extra"
  contents_new_oid="$(calc_oid "$contents_new")"
  contents_new_oid_short="$(echo $contents_new_oid | head -c 7)"

  printf "%s" "$contents_new" > a.dat
  git add a.dat

  expected="On branch main

Objects to be committed:

	a.dat (Git: $contents_oid_short -> LFS: $contents_new_oid_short)

Objects not staged for commit:"
  actual="$(git lfs status)"

  [ "$expected" = "$actual" ]
)
end_test

begin_test "status: Git to LFS conversion"
(
  set -e

  reponame="status-git-to-lfs-conversion"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  contents="contents"
  contents_oid="$(calc_oid "$contents")"
  contents_oid_short="$(echo "$contents_oid" | head -c 7)"

  printf "%s" "$contents" > a.dat
  git add a.dat
  git commit -m "add a.dat"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "track *.dat"

  git push origin main

  pushd "$TRASHDIR" > /dev/null
    clone_repo "$reponame" "$reponame-2"

    git add a.dat

    git lfs status 2>&1 | tee status.log
    if [ "0" -ne "${PIPESTATUS[0]}" ]; then
      echo >&2 "git lfs status should have succeeded, didn't ..."
      exit 1
    fi

    expected="On branch main
Objects to be pushed to origin/main:


Objects to be committed:

	a.dat (Git: $contents_oid_short -> LFS: $contents_oid_short)

Objects not staged for commit:"
    actual="$(cat status.log)"

    [ "$expected" = "$actual" ]
  popd > /dev/null
)
end_test

begin_test "status (missing objects)"
(
  set -e

  reponame="status-missing-objects"
  git init "$reponame"
  cd "$reponame"

  git lfs track "*.dat"
  printf "a" > a.dat

  git add .gitattributes a.dat
  git commit -m "initial commit"

  # Remove the original object "a.dat" (ensure '--no-filters' is not given).
  oid="$(git hash-object -t blob -- a.dat)"
  rm -rf ".git/objects/${oid:0:2}/${oid:2}"

  # Create an unstaged change against a source file that doesn't exist.
  printf "b" > a.dat
  git add a.dat

  git lfs status \
    | grep "a.dat (?: <missing> -> LFS: $(calc_oid b | head -c 7))"
)
end_test

begin_test "status (unpushed objects)"
(
  set -e

  reponame="status-unpushed-objects"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  git push -u origin main

  contents="a"
  oid="$(calc_oid "$contents")"
  printf "%s" "$contents" > a.dat

  git add a.dat
  git commit -m "add a large file"

  expected="On branch main
Objects to be pushed to origin/main:

	a.dat ($oid)

Objects to be committed:


Objects not staged for commit:"

  [ "$expected" = "$(git lfs status)" ]
)
end_test

begin_test "status (without a working copy)"
(
  reponame="status-no-working-copy.git"

  git init --bare "$reponame"
  cd "$reponame"

  git lfs status 2>&1 | tee status.log
  if [ "0" -eq "${PIPESTATUS[0]}" ]; then
    echo >&2 "git lfs status should have failed, didn't ..."
    exit 1
  fi
  [ "This operation must be run in a work tree." = "$(cat status.log)" ]
)
end_test

begin_test "status (deleted files)"
(
  set -e

  reponame="status-deleted-files"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  git push -u origin main

  contents="a"
  oid="$(calc_oid "$contents")"
  oid_short="$(calc_oid "$contents" | head -c 7)"
  printf "%s" "$contents" > a.dat

  git add a.dat
  git commit -m "add a large file"

  git rm a.dat

  expected="On branch main
Objects to be pushed to origin/main:

	a.dat ($oid)

Objects to be committed:

	a.dat (LFS: $oid_short -> File: deleted)

Objects not staged for commit:"

  [ "$expected" = "$(git lfs status)" ]
)
end_test

begin_test "status (file to dir)"
(
  set -e

  reponame="status-file-to-dir"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  printf 'file' > test
  git add test
  git commit -m "add test"

  obj=$(calc_oid "file" | head -c 7)

  git rm test
  mkdir test

  contents="a"
  oid="$(calc_oid "$contents")"
  oid_short="$(calc_oid "$contents" | head -c 7)"
  printf "%s" "$contents" > test/a.dat

  git add test
  git commit -m "add files"

  git reset HEAD~
  git add test

  expected="On branch main

Objects to be committed:

	test (Git: $obj -> File: deleted)
	test/a.dat (LFS: $oid_short)

Objects not staged for commit:"

  [ "$expected" = "$(git lfs status)" ]
)
end_test


begin_test "status: permission change"
(
  set -e

  # We're using chmod below.
  if [ "$IS_WINDOWS" -eq 1 ]; then
    exit 0
  fi

  reponame="status-permission-change"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  contents="contents"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "track *.dat"

  printf "%s" "$contents" > a.dat
  git add a.dat
  git commit -m "add a.dat"

  chmod 400 a.dat

  # A permission change should not result in any output.
  git lfs status 2>&1 | tee status.log
  if [ "0" -ne "${PIPESTATUS[0]}" ]; then
    echo >&2 "git lfs status should have succeeded, didn't ..."
    exit 1
  fi

  expected="On branch main

Objects to be committed:


Objects not staged for commit:"
  actual="$(cat status.log)"

  [ "$expected" = "$actual" ]
)
end_test
