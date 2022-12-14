#!/usr/bin/env bash
# This is a sample Git LFS test.  See test/README.md and testhelpers.sh for
# more documentation.

. "$(dirname "$0")/testlib.sh"

begin_test "batch transfer"
(
  set -e

  # This initializes a new bare git repository in test/remote.
  # These remote repositories are global to every test, so keep the names
  # unique.
  reponame1="$(basename "$0" ".sh")"
  reponame2="CAPITALLETTERS"
  reponame=$reponame1$reponame2
  setup_remote_repo "$reponame"

  # Clone the repository from the test Git server.  This is empty, and will be
  # used to test a "git pull" below. The repo is cloned to $TRASHDIR/clone
  clone_repo "$reponame" clone

  # Clone the repository again to $TRASHDIR/repo. This will be used to commit
  # and push objects.
  clone_repo "$reponame" repo

  # This executes Git LFS from the local repo that was just cloned.
  git lfs track "*.dat" 2>&1 | tee track.log
  grep "Tracking \"\*.dat\"" track.log

  contents="a"
  contents_oid=$(calc_oid "$contents")

  printf "%s" "$contents" > a.dat
  git add a.dat
  git add .gitattributes
  git commit -m "add a.dat" 2>&1 | tee commit.log
  grep "main (root-commit)" commit.log
  grep "2 files changed" commit.log
  grep "create mode 100644 a.dat" commit.log
  grep "create mode 100644 .gitattributes" commit.log

  [ "a" = "$(cat a.dat)" ]

  # This is a small shell function that runs several git commands together.
  assert_pointer "main" "a.dat" "$contents_oid" 1

  refute_server_object "$reponame" "$contents_oid"

  # This pushes to the remote repository set up at the top of the test.
  git push origin main 2>&1 | tee push.log
  grep "Uploading LFS objects: 100% (1/1), 1 B" push.log
  grep "main -> main" push.log

  assert_server_object "$reponame" "$contents_oid"

  # change to the clone's working directory
  cd ../clone

  git pull origin main

  [ "a" = "$(cat a.dat)" ]

  assert_pointer "main" "a.dat" "$contents_oid" 1
)
end_test

begin_test "batch transfers occur in reverse order by size"
(
  set -e

  reponame="batch-order-test"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  git add .gitattributes
  git commit -m "initial commit"

  small_contents="small"
  small_oid="$(calc_oid "$small_contents")"
  printf "%s" "$small_contents" > small.dat

  bigger_contents="bigger"
  bigger_oid="$(calc_oid "$bigger_contents")"
  printf "%s" "$bigger_contents" > bigger.dat

  git add *.dat
  git commit -m "add small and large objects"

  GIT_CURL_VERBOSE=1 git push origin main 2>&1 | tee push.log

  batch="$(grep "{\"operation\":\"upload\"" push.log | head -1)"

  pos_small="$(substring_position "$batch" "$small_oid")"
  pos_large="$(substring_position "$batch" "$bigger_oid")"

  # Assert that the larger object shows up earlier in the batch than the
  # smaller object
  [ "$pos_large" -lt "$pos_small" ]
)
end_test

begin_test "batch transfers succeed with an empty hash algorithm"
(
  set -e

  reponame="batch-test-empty-algo"
  contents="batch-hash-algo-empty"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  printf "hi" > good.dat
  printf "%s" "$contents" > special.dat
  git add .gitattributes good.dat special.dat
  git commit -m "hi"

  git push origin main 2>&1 | tee push.log
  assert_server_object "$reponame" "$(calc_oid "$contents")"
)
end_test

begin_test "batch transfers fail with an unknown hash algorithm"
(
  set -e

  reponame="batch-test-invalid-algo"
  contents="batch-hash-algo-invalid"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  git lfs track "*.dat"
  printf "hi" > good.dat
  printf "%s" "$contents" > special.dat
  git add .gitattributes good.dat special.dat
  git commit -m "hi"

  git push origin main 2>&1 | tee push.log
  grep 'unsupported hash algorithm' push.log
  refute_server_object "$reponame" "$(calc_oid "$contents")"
)
end_test

begin_test "batch transfers with ssh endpoint (git-lfs-authenticate)"
(
  set -e

  reponame="batch-ssh"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  sshurl="${GITSERVER/http:\/\//ssh://git@}/$reponame"
  git config lfs.url "$sshurl"

  contents="test"
  git lfs track "*.dat"
  printf "%s" "$contents" > test.dat
  git add .gitattributes test.dat
  git commit -m "initial commit"

  git push origin main 2>&1
)
end_test

begin_test "batch transfers with ssh endpoint (git-lfs-transfer)"
(
  set -e

  setup_pure_ssh

  reponame="batch-ssh-transfer"
  setup_remote_repo "$reponame"
  clone_repo "$reponame" "$reponame"

  sshurl=$(ssh_remote "$reponame")
  git config lfs.url "$sshurl"

  contents="test"
  git lfs track "*.dat"
  printf "%s" "$contents" > test.dat
  git add .gitattributes test.dat
  git commit -m "initial commit"

  git push origin main 2>&1
  cd ..
  GIT_TRACE=1 git clone "$sshurl" "$reponame-2" 2>&1 | tee trace.log
  grep "lfs-ssh-echo.*git-lfs-transfer .*$reponame.git download" trace.log
  cd "$reponame-2"
  git lfs fsck
)
end_test
