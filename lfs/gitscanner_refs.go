package lfs

import (
	"encoding/hex"
	"sync"

	"github.com/git-lfs/git-lfs/v3/config"
	"github.com/git-lfs/git-lfs/v3/git"
	"github.com/git-lfs/git-lfs/v3/tr"
)

type lockableNameSet struct {
	opt *ScanRefsOptions
	set GitScannerSet
}

// Determines if the given blob sha matches a locked file.
func (s *lockableNameSet) Check(blobSha string) (string, bool) {
	if s == nil || s.opt == nil || s.set == nil {
		return "", false
	}

	name, ok := s.opt.GetName(blobSha)
	if !ok {
		return name, ok
	}

	if s.set.Contains(name) {
		return name, true
	}
	return name, false
}

func noopFoundLockable(name string) {}

// scanRefsToChan scans through all unique objects reachable from the
// "include" refs and not reachable from any "exclude" refs and invokes the
// provided callback for each pointer file, valid or invalid, that it finds.
// Reports unique OIDs once only, not multiple times if more than one file
// has the same content.
func scanRefsToChan(scanner *GitScanner, pointerCb GitScannerFoundPointer, include, exclude []string, gitEnv, osEnv config.Environment, opt *ScanRefsOptions) error {
	if opt == nil {
		panic(tr.Tr.Get("no scan ref options"))
	}

	revs, err := revListShas(include, exclude, opt)
	if err != nil {
		return err
	}

	lockableSet := &lockableNameSet{opt: opt, set: scanner.PotentialLockables}
	smallShas, batchLockableCh, err := catFileBatchCheck(revs, lockableSet)
	if err != nil {
		return err
	}

	lockableCb := scanner.FoundLockable
	if lockableCb == nil {
		lockableCb = noopFoundLockable
	}

	go func(cb GitScannerFoundLockable, ch chan string) {
		for name := range ch {
			cb(name)
		}
	}(lockableCb, batchLockableCh)

	pointers, checkLockableCh, err := catFileBatch(smallShas, lockableSet, gitEnv, osEnv)
	if err != nil {
		return err
	}

	for p := range pointers.Results {
		if name, ok := opt.GetName(p.Sha1); ok {
			p.Name = name
		}

		if scanner.Filter.Allows(p.Name) {
			pointerCb(p, nil)
		}
	}

	for lockableName := range checkLockableCh {
		if scanner.Filter.Allows(lockableName) {
			lockableCb(lockableName)
		}
	}

	if err := pointers.Wait(); err != nil {
		pointerCb(nil, err)
	}

	return nil
}

// scanRefsToChanSingleIncludeExclude scans through all unique objects
// reachable from the "include" ref and not reachable from the "exclude" ref
// and invokes the provided callback for each pointer file, valid or invalid,
// that it finds.
// Reports unique OIDs once only, not multiple times if more than one file
// has the same content.
func scanRefsToChanSingleIncludeExclude(scanner *GitScanner, pointerCb GitScannerFoundPointer, include, exclude string, gitEnv, osEnv config.Environment, opt *ScanRefsOptions) error {
	return scanRefsToChan(scanner, pointerCb, []string{include}, []string{exclude}, gitEnv, osEnv, opt)
}

// scanRefsToChanSingleIncludeMultiExclude scans through all unique objects
// reachable from the "include" ref and not reachable from any "exclude" refs
// and invokes the provided callback for each pointer file, valid or invalid,
// that it finds.
// Reports unique OIDs once only, not multiple times if more than one file
// has the same content.
func scanRefsToChanSingleIncludeMultiExclude(scanner *GitScanner, pointerCb GitScannerFoundPointer, include string, exclude []string, gitEnv, osEnv config.Environment, opt *ScanRefsOptions) error {
	return scanRefsToChan(scanner, pointerCb, []string{include}, exclude, gitEnv, osEnv, opt)
}

// scanRefsByTree scans through all objects reachable from the "include" refs
// and not reachable from any "exclude" refs and invokes the provided callback
// for each pointer file, valid or invalid, that it finds.
// Objects which appear in multiple trees will be visited once per tree.
func scanRefsByTree(scanner *GitScanner, pointerCb GitScannerFoundPointer, include, exclude []string, gitEnv, osEnv config.Environment, opt *ScanRefsOptions) error {
	if opt == nil {
		panic(tr.Tr.Get("no scan ref options"))
	}

	revs, err := revListShas(include, exclude, opt)
	if err != nil {
		return err
	}

	errchan := make(chan error, 20) // multiple errors possible
	wg := &sync.WaitGroup{}

	for r := range revs.Results {
		wg.Add(1)
		go func(rev string) {
			defer wg.Done()
			err := runScanTreeForPointers(pointerCb, rev, gitEnv, osEnv)
			if err != nil {
				errchan <- err
			}
		}(r)
	}

	wg.Wait()
	close(errchan)
	for err := range errchan {
		if err != nil {
			return err
		}
	}

	return revs.Wait()
}

// revListShas uses git rev-list to return the list of object sha1s
// for the given ref. If all is true, ref is ignored. It returns a
// channel from which sha1 strings can be read.
func revListShas(include, exclude []string, opt *ScanRefsOptions) (*StringChannelWrapper, error) {
	scanner, err := git.NewRevListScanner(include, exclude, &git.ScanRefsOptions{
		Mode:             git.ScanningMode(opt.ScanMode),
		Remote:           opt.RemoteName,
		SkipDeletedBlobs: opt.SkipDeletedBlobs,
		SkippedRefs:      opt.skippedRefs,
		Mutex:            opt.mutex,
		Names:            opt.nameMap,
		CommitsOnly:      opt.CommitsOnly,
	})

	if err != nil {
		return nil, err
	}

	revs := make(chan string, chanBufSize)
	errs := make(chan error, 5) // may be multiple errors

	go func() {
		for scanner.Scan() {
			sha := hex.EncodeToString(scanner.OID())
			if name := scanner.Name(); len(name) > 0 {
				opt.SetName(sha, name)
			}
			revs <- sha
		}

		if err = scanner.Err(); err != nil {
			errs <- err
		}

		if err = scanner.Close(); err != nil {
			errs <- err
		}

		close(revs)
		close(errs)
	}()

	return NewStringChannelWrapper(revs, errs), nil
}
