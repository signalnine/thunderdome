package gitops

// ShortHashForTest exposes the unexported shortHash helper to the test package.
var ShortHashForTest = shortHash

// StripNonRepoHunksForTest exposes the unexported stripNonRepoHunks helper.
var StripNonRepoHunksForTest = stripNonRepoHunks

// CleanupTmpDirForTest exposes the unexported cleanupTmpDir helper.
var CleanupTmpDirForTest = cleanupTmpDir

// IsSafeTmpDirForTest exposes the unexported isSafeTmpDir guard.
var IsSafeTmpDirForTest = isSafeTmpDir
