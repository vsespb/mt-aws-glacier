## Bug reports:

1. provide full output after error.

2. provide perl version - `perl -V`

## Pull requests:

1. Use only Perl Core modules (in core since 5.8.8) in code. Exceptions to this rule can be discussed.

2. You can use non-core modules for testsuite

3. Don't use bad modules in testsuite, check that it's still supported, bugs sometimes fixed, testsuite exists, no huge bugs, and CPANTESTERS shows good pass rate for target platforms.

4. Code should work in any perl from 5.8.8 to latest version.

5. I did not try hard to make it work (in the future) under Win32, so you should not too.

6. Use POSIX system calls (should be available under *BSD, Solaris, Linux, MacOSX and any POSIX), on all supported versions of distributions.

7. There are some legacy tests in code, for testing Test::Deep + (Test::Spec OR simple testing using "local .. sub") is preferred now.

8. You change should not break tests (or you should fix it)

9. Patches with testsuite preferred.

10. No Try::Tiny yet, sorry.

11. TABs should be used for indentation, spaces for aligment, no trailing spaces.
