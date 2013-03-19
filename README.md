mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon Glacier service.

## Intro

Amazon Glacier is an archive/backup service with very low storage price. However with some caveats in usage and archive retrieval prices.
[Read more about Amazon Glacier][amazon glacier] 

mt-aws-glacier is a client application for Glacier.

[amazon glacier]:http://aws.amazon.com/glacier/

## Version

* Version 0.936 beta (See [ChangeLog][mt-aws glacier changelog])

[mt-aws glacier changelog]:https://github.com/vsespb/mt-aws-glacier/blob/master/ChangeLog

## Features

* Does not use any existing Amazon Glacier library, so can be flexible in implementing advanced features
* Glacier Multipart upload
* Multithreaded upload
* Multipart+Multithreaded upload
* Multithreaded retrieval, deletion and download
* Tracking of all uploaded files with a local journal file (opened for write in append mode only)
* Checking integrity of local files using journal
* Ability to limit number of archives to retrieve
* File name and modification times are stored as Glacier metadata ([metadata format for developers][mt-aws-glacier Amazon Glacier meta-data format specification])
* Ability to re-create journal file from Amazon Glacier metadata
* Full UTF-8 support (and full single-byte encoding support undef *BSD systems) 
* Upload from STDIN
* User selectable HTTPS support. Currently defaults to plaintext HTTP

## Coming-soon features

* Multipart download (using HTTP Range header)
* Use journal file as flock() mutex
* Checking integrity of remote files
* Some integration with external world, ability to read SNS topics
* Simplified distribution for Debian/RedHat
* Split code to re-usable modules, publishing on CPAN (Currently there are great existing Glacier modules on CPAN - see [Net::Amazon::Glacier][Amazon Glacier API CPAN module - Net::Amazon::Glacier] by *Tim Nordenfur*) 


[Amazon Glacier API CPAN module - Net::Amazon::Glacier]:https://metacpan.org/module/Net::Amazon::Glacier 
[mt-aws-glacier Amazon Glacier meta-data format specification]:https://github.com/vsespb/mt-aws-glacier/blob/master/lib/App/MtAws/MetaData.pm

## Planned next version features

* Amazon S3 support

## Important bugs/missed features

* Zero length files are ignored
* Only multipart upload implemented, no plain upload
* Mac OS X filesystem treated as case-sensitive

## Production Readiness

* Not recommended to use in production until first "Release" version. Currently Beta.

## Installation/System requirements

Script is made for Linux OS. Tested under Ubuntu and Debian. Should work under other Linux distributions. Lightly tested under Mac OS X.
Should NOT work under Windows. 

* Install the following CPAN modules:

	* **LWP::UserAgent** (or Debian package **libwww-perl** or RPM package **perl-libwww-perl** or MacPort **p5-libwww-perl**)
	* **JSON::XS** (or Debian package **libjson-xs-perl** or RPM package **perl-JSON-XS** or MacPort **p5-json-XS**)

	* for older Perl < 5.9.3 (i.e. CentOS 5.x), install also **Digest::SHA** (or Debian package **libdigest-sha-perl** or RPM package **perl-Digest-SHA**)
	* on some old Linux installations (examples: Ubuntu 10.04, CentOS 5.x) to use HTTPS you need to install **LWP::UserAgent::https** via CPAN: `cpan -i LWP::UserAgent::https`
	or `cpanp -i LWP::UserAgent::https` If `perl -MLWP -e 'print LWP->VERSION()'` prints 6.x version - everything is installed already.


* Install mt-aws-glacier

		git clone https://github.com/vsespb/mt-aws-glacier.git

	(or just download and unzip `https://github.com/vsespb/mt-aws-glacier/archive/master.zip` )

	After that you can execute `mtglacier` command from any directory, or create a symlink to it - it will find other package files by itself.

## Warnings ( *MUST READ* )

* When playing with Glacier make sure you will be able to delete all your archives, it's impossible to delete archive
or non-empty vault in amazon console now. Also make sure you have read _all_ Amazon Glacier pricing/faq.

* Read their pricing [FAQ][Amazon Glacier faq] again, really. Beware of retrieval fee.

* With low "partsize" option you pay a bit more (Amazon charges for each upload request)

* With high partsize*concurrency there is a risk of getting network timeouts HTTP 408/500.

* Memory usage (for 'sync') formula is ~ min(NUMBER_OF_FILES_TO_SYNC, max-number-of-files) + partsize*concurrency

* For backup created with older versions (0.7x) of mt-aws-glacier, Journal file **required to restore backup**.


[Amazon Glacier faq]:http://aws.amazon.com/glacier/faqs/#How_will_I_be_charged_when_retrieving_large_amounts_of_data_from_Amazon_Glacier

## Usage
 
1. Create a directory containing files to backup. Example `/data/backup`
2. Create config file, say, glacier.cfg

		key=YOURKEY
		secret=YOURSECRET
		# region: eu-west-1, us-east-1 etc
		region=us-east-1
		# protocol=http (default) or https
		protocol=http

	(you can skip any config option and specify it directly in command line)
3. Create a vault in specified region, using Amazon Console (`myvault`) or using mtglacier

		./mtglacier create-vault myvault --config=glacier.cfg

	(note that Amazon Glacier does not return error if vault already exists etc)

4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

		./mtglacier sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=3

6. Add more files and sync again
7. Check that your local files not modified since last sync

		./mtglacier check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
8. Delete some files from your backup location
9. Initiate archive restore job on Amazon side

		./mtglacier restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=10

10. Wait 4+ hours for Amazon Glacier to complete archive retrieval
11. Download restored files back to backup location

		./mtglacier restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log

12. Delete all your files from vault

		./mtglacier purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log
		
13. Wait ~ 24-48 hours and you can try deleting your vault

		./mtglacier delete-vault myvault --config=glacier.cfg 

	(note: currently Amazon Glacier does not return error if vault is not exists)

## Restoring journal

In case you lost your journal file, you can restore it from Amazon Glacier metadata

1. Run retrieve-inventory command. This will request Amazon Glacier to prepare vault inventory.

		./mtglacier retrieve-inventory --config=glacier.cfg --vault=myvault

2. Wait 4+ hours for Amazon Glacier to complete inventory retrieval (also note that you will get only ~24h old inventory..)

3. Download inventory and export it to new journal (this sometimes can be pretty slow even if inventory is small, wait a few minutes):

		./mtglacier download-inventory --config=glacier.cfg --vault=myvault --new-journal=new-journal.log


For files created by mt-aws-glacier version 0.8x and higher original filenames will be restored. For other files archive_id will be used as filename. See Amazon Glacier metadata format for mt-aws-glacier here: [Amazon Glacier metadata format used by mt-aws glacier][Amazon Glacier metadata format used by mt-aws glacier]

[Amazon Glacier metadata format used by mt-aws glacier]:https://github.com/vsespb/mt-aws-glacier/blob/86031708866c7b444b6f8efa4900f42536c91c5a/MetaData.pm#L35

## Other commands

### `upload-file`

Uploads a single file into Amazon Glacier. File will be tracked with Journal (just like when using `sync` command).

There are several possible combinations of options for `upload-file`:

1. **--filename** and **--dir**
	
	_Uploads what_: a file, pointed by `filename`.
	
	_Filename in Journal and Amazon Glacier metadata_: A relative path from `dir` to `filename`

		./mtglacier upload-file --config=glacier.cfg --vault=myvault --journal=journal.log --dir /data/backup --filename=/data/backup/dir1/myfile
		
	(this will upload content of `/data/backup/dir1/myfile` to Amazon Glacier and use `dir1/myfile` as filename for Journal )

		./mtglacier upload-file --config=glacier.cfg --vault=myvault --journal=journal.log --dir data/backup --filename=data/backup/dir1/myfile
		
	(Let's assume current directory is `/home`. Then this will upload content of `/home/data/backup/dir1/myfile` to Amazon Glacier and use `dir1/myfile` as filename for Journal)
	
	(NOTE: file `filename` should be inside directory `dir`)

2. **--filename** and  **--set-rel-filename**
	
	_Uploads what_: a file, pointed by `filename`.
	
	_Filename in Journal and Amazon Glacier metadata_: As specified in `set-rel-filename`

		./mtglacier upload-file --config=glacier.cfg --vault=myvault --journal=journal.log --filename=/tmp/myfile --set-rel-filename a/b/c
		
	(this will upload content of `/tmp/myfile` to Amazon Glacier and use `a/b/c` as filename for Journal )

	(NOTE: `set-rel-filename` should be a _relative_ filename i.e. must not start with `/`)

3. **--stdin**, **--set-rel-filename** and **--check-max-file-size**
	
	_Uploads what_: a file, read from STDIN
	
	_Filename in Journal and Amazon Glacier metadata_: As specified in `set-rel-filename`

	Also, as file size is not known until the very end of upload, need to be sure that file will not exceed 10 000 parts limit, and you must
	specify `check-max-file-size` -- maximum possible size of file (in Megabytes), that you can expect. What this option do is simply throw error
	if `check-max-file-size`/`partsize` > 10 000 parts (in that case it's recommended to adjust `partsize`). That's all. I remind that you can put this (and
	any other option to config file)
	
	
		./mtglacier upload-file --config=glacier.cfg --vault=myvault --journal=journal.log --stdin --set-rel-filename path/to/file --check-max-file-size=131
		
	(this will upload content of file read from STDIN to Amazon Glacier and use `path/to/file` as filename for Journal. )

	(NOTE: `set-rel-filename` should be a _relative_ filename i.e. must not start with `/`)


NOTES:

1. In the current version of mtglacier you are disallowed to store multiple versions of same file. I.e. upload multiple files with same relative filename
to a single Amazon Glacier vault and single Journal. Simple file versioning will be implemented in the future versions.

2. You can use other optional options with this command (`concurrency`, `partsize`)

## File selection options

`filter`, `include`, `exclude` options allow you to construct a list of RULES to select only certain files for the operation.
Can be used with commands: `sync`, `purge-vault`, `restore`, `restore-completed ` and `check-local-hash`

+ **--filter**

	Adds one or several RULES to the list of rules. One filter value can contain multiple rules, it has same effect as multiple filter values with one
	RULE each.
	
		--filter='RULE1 RULE2' --filter 'RULE3'

	is same as

		--filter 'RULE1 RULE2 RULE3'


	RULES should be a sequence of PATTERNS, followed by '+' or '-' and separated by a spaces. There can be a space between '+'/'-' and PATTERN.

		RULES: [+-]PATTERN [+-]PATTERN ...


	'+' means INCLUDE PATTERN, '-' means EXCLUDE PATTERN


	NOTES:
	
		1. If RULES contain spaces or wildcards, you must quote it when running `mtglacier` from Shell (Example: `mtglacier ... --filter -tmp/` but `mtglacier --filter '-log/ -tmp/'`)


		2. Although, PATTERN can contain spaces, you cannot use if, because RULES separated by a space(s).


		3. PATTERN can be empty (Example: `--filter +data/ --filter -` - excludes everything except any directory with name `data`, last pattern is empty)


		4. Unlike other options, `filter`, `include` and `exclude` cannot be used in config file (in order to avoid mess with order of rules)


+ **--include**

	Adds an INCLUDE PATTERN to list of rules (Example: `--include /data/ --filter '+/photos/ -'` - include only photos and data directories)

+ **--exclude**

	Adds an EXCLUDE PATTERN to list of rules (Example: `--exclude /data/` - include everything except /data and subdirectories)
	
	NOTES:

		1. You can use spaces in PATTERNS here (Example: `--exclude '/my documents/'` - include everything except "/my documents" and subdirectories)


+ **How PATTERNS work**

+ 1)  If the pattern starts with a '/' then it is anchored to a particular spot in the hierarchy of files, otherwise it is matched against the final
component of the filename.

		`/tmp/myfile` - matches only `/tmp/myfile`. But `tmp/myfile` - matches `/tmp/myfile` and `/home/john/tmp/myfile`

+ 2) If the pattern ends with a '/' then it will only match a directory and all files/subdirectories inside this directory. It won't match regular file.
Note that if directory is empty, it won't be synchronized to Amazon Glacier, as it does not support directories

		`log/` - matches only directory `log`, but not a file `log`

+ 3) If pattern does not end with a '/', it won't match directory (directories are not supported by Amazon Glacier, so it makes no sense to match a directory
without subdirectories). However if, in future versions, we find a way to store empty directories in Amazon Glacier, this behavior may change.

		`log` - matches only file `log`, but not a directory `log` nor files inside it

+ 4) if the pattern contains a '/' (not counting a trailing '/') then it is matched against the full pathname, including any leading directories.
Otherwise it is matched only against the final component of the filename.

		`myfile` - matches `myfile` in any directory (i.e. matches both `/home/ivan/myfile` and `/data/tmp/myfile`), but it does not match
		`/tmp/myfile/myfile1`. While `tmp/myfile` matches `/data/tmp/myfile` and `/tmp/myfile/myfile1`

+ 5) Wildcard '*' matches zero or more characters, but it stops at slashes.

		`/tmp*/file` matches `/tmp/file`, `/tmp1/file`, `/tmp2/file` but not `tmp1/x/file`

+ 6) Wildcard '**' matches anything, including slashes.

		`/tmp**/file` matches `/tmp/file`, `/tmp1/file`, `/tmp2/file`, `tmp1/x/file` and `tmp1/x/y/z/file`

+ 7) When wildcard '**' meant to be a separated path component (i.e. surrounded with slashes/beginning of line/end of line), it matches 0 or more subdirectories.

		`/foo/**/bar` matches `foo/bar` and `foo/x/bar`. Also `**/file` matches `/file` and `x/file`

+ 8) Wildcard '?' matches any (exactly one) character except a slash ('/').

		`??.txt` matches `11.txt`, `xy.txt` but not `abc.txt`

+ 9) if PATTERN is empty, it matches anything.

		`mtglacier ... --filter '+data/ -'` - Last pattern is empty string (followed by '-')

+ 10) If PATTERN is started with '!' it only match when rest of pattern (i.e. without '!') does not match.

		`mtglacier ... --filter '-!/data/ +*.gz'` - include only `*.gz` files inside `data/` directory. 

+ **How rules are processed**

+ 1) A filename is checked against rules in the list. Once filename match PATTERN, file is included or excluded depending on the kind of PATTERN matched.
No other rules checked after first match.

		`--filter '+*.txt -file.txt'` File `file.txt` is INCLUDED, it matches 1st pattern, so 2nd pattern is ignored

+ 2) If no rules matched - file is included (default rule is INCLUDE rule).

		`--filter '+*.jpeg'` File `file.txt` is INCLUDED, as it does not match any rules

+ 3) When we process both local files and Journal filelist (sync, restore commands), rule applied to BOTH sides.

+ 4) When traverse directory tree, (in contrast to behavior of some tools, like _Rsync_), if a directory (and all subdirectories) match exclude pattern,
directory tree is not pruned, traversal go into the directory. So this will work fine (it will include `/tmp/data/a/b/c`, but exclude all other files in `/tmp/data`):

		--filter '+/tmp/data/a/b/c -/tmp/data +'

+ 5) In some cases, to reduce disk IO, directory traversal into excluded directory can be stopped.
This only can happen when `mtglacier` absolutely sure that it won't break behavior (4) described above.
Currently it's guaranteed that traversal stop only in case when:

+ A directory match EXCLUDE rule without '!' prefix, ending with '/' or '**', or empty rule

+ AND there are no INCLUDE rules before this EXCLUDE RULE

		`--filter '-*.tmp -/media/ -/proc/ +*.jpeg'` - system '/proc' and huge '/media' directory is not traversed. 

## Additional command line options

1. `concurrency` (with `sync`, `upload-file`, `restore`, `restore-completed` commands) - number of parallel upload streams to run. (default 4)

		--concurrency=4

2. `partsize` (with `sync`, `upload-file` command) - size of file chunk to upload at once, in Megabytes. (default 16)

		--partsize=16

3. `max-number-of-files` (with `sync` or `restore` commands) - limit number of files to sync/restore. Program will finish when reach this limit.

		--max-number-of-files=100

4. `key/secret/region/vault/protocol` - you can override any option from config

5. `dry-run` (with `sync`, `purge-vault`, `restore`, `restore-completed ` and even `check-local-hash` commands) - do not perform actual work, print what will happen instead. 

		--dry-run

## Configuring Character Encodings

Autodetection of locale/encodings not implemented yet, but currently there is ability to tune encodings manually.

Below 4 options, that can be used in config file and in command line.

1. `terminal-encoding` - Encoding of your terminal (STDOUT/STDERR for system messages)

2. `filenames-encoding` - Encoding of filenames in filesystem.

	Under most *nix filesystems filenames stored as byte sequences, not characters. So in theory application is responsible for managing encodings. 

3. `config-encoding` - Encoding of your config file (`glacier.cfg` in examples above)

4. `journal-encoding` - Encoding to be used for Journal file (when reading and writing journal specified with `--journal` and `--new-journal` options)


Default value for all options is 'UTF-8'. Under Linux and Mac OS X you usually don't need to change encodings.
Under *BSD systems often single-byte encodings are used. Most likely yo'll need to change `terminal-encoding` and `filenames-encoding`. Optionaly you can also
change `config-encoding` and `journal-encoding`.

Notes:

* Before switching `config-encoding` and `journal-encoding` you are responsible for transcoding file content of config and journal files manually.

* You are responsible for encoding compatibility. For example Don't try to work with UTF-8 journal with non-Cyrilic characters and KOI8-R (Cyrilic) filesystem.

* Don't try to use UTF-16 for *nix filesystem. It's not ASCII compatible and contains \x00 bytes, which can't be stored in filesystem.

* Don't use `UTF8` - it does not validate data, use `UTF-8` (one with a dash) instead.

* To get list of encodings installed with your Perl run:

		perl -MEncode -e 'print join qq{\n}, Encode->encodings(q{:all})'
		
* Config file name (specified with `--config`) can be in any encoding (it's used as is) Of course it will work only if your terminal encoding match your
filesystem encoding or if your config file name consists of ASCII-7bit characters only.

* Additional information about encoding support in Perl: [CPAN module Encode::Supported](http://search.cpan.org/perldoc?Encode%3A%3ASupported)

* Amazon Glacier metadata (on Amazon servers) is always stored in UTF-8. No way to override it. You can use Journal in any encoding with same
metdata without problems and you can dump metadata to journals with different encodings (using `download-inventory` command)

* See also [convmv tool](http://www.j3e.de/linux/convmv/man/)

## Test/Play with it

1. create empty dir MYDIR
2. Set vault name inside `cycletest.sh`
3. Run

		./cycletest.sh init MYDIR
		./cycletest.sh retrieve MYDIR
		./cycletest.sh restore MYDIR

* OR

		./cycletest.sh init MYDIR
		./cycletest.sh purge MYDIR

## Help/contribute this project

* If you are using it and like it, please "Star" it on GitHUb, this way you'll help promote the project
* Please report any bugs or issues (using GitHub issues). Well, any feedback is welcomed.
* If you want to contribute to the source code, please contact me first and describe what you want to do

## Minimum Amazon Glacier permissions:

Something like this (including permissions to create/delete vaults):

	{
	"Statement": [
		{
		"Effect": "Allow",
		"Resource":["arn:aws:glacier:eu-west-1:*:vaults/test1",
			"arn:aws:glacier:us-east-1:*:vaults/test1",
			"arn:aws:glacier:eu-west-1:*:vaults/test2",
			"arn:aws:glacier:eu-west-1:*:vaults/test3"],
			"Action":["glacier:UploadArchive",
			  "glacier:InitiateMultipartUpload",
			  "glacier:UploadMultipartPart",
			  "glacier:UploadPart",
			  "glacier:DeleteArchive",
			  "glacier:ListParts",
			  "glacier:InitiateJob",
			  "glacier:ListJobs",
			  "glacier:GetJobOutput",
			  "glacier:ListMultipartUploads",
			  "glacier:CompleteMultipartUpload"] 
		},
		{
			"Effect": "Allow",
			"Resource":["arn:aws:glacier:eu-west-1:*",
			  "arn:aws:glacier:us-east-1:*"],
			"Action":["glacier:CreateVault",
			  "glacier:DeleteVault"] 
		}
		]
	}


#### EOF

[![mt-aws glacier tracking pixel](https://mt-aws.com/mt-aws-glacier-transp.gif "mt-aws glacier tracking pixel")](http://mt-aws.com/)

