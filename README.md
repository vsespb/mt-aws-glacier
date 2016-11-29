mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon Glacier service.

## Intro

Amazon Glacier is an archive/backup service with very low storage price. However there are some caveats in usage and archive retrieval prices.
[Read more about Amazon Glacier][amazon glacier]

*mt-aws-glacier* is a client application for Amazon Glacier, written in the Perl programming language, for *nix.

[amazon glacier]:http://aws.amazon.com/glacier/

## Version

* Version 1.120 (See [ChangeLog][mt-aws glacier changelog] or follow [@mtglacier](https://twitter.com/mtglacier) for updates)  [![Build Status](https://travis-ci.org/vsespb/mt-aws-glacier.png?branch=master)](https://travis-ci.org/vsespb/mt-aws-glacier)

[mt-aws glacier changelog]:https://github.com/vsespb/mt-aws-glacier/blob/master/ChangeLog

## Contents

* [Features](#features)

* [Important bugs/missing features](#important-bugsmissing-features)

* [Production readiness](#production-readiness)

* [Installation/System requirements](#installationsystem-requirements)

	* [Installation via OS package manager](#installation-via-os-package-manager)

	* [Manual installation](#manual-installation)

	* [Installation via CPAN](#or-installation-via-cpan)

	* [Installation general instructions, troubleshooting, edge cases and misc instructions](#installation-general-instructions-troubleshooting-edge-cases-and-misc-instructions)

* [Warnings ( MUST READ )](#warnings--must-read-)

* [Help/contribute this project](#helpcontribute-this-project)

* [Usage](#usage)

* [Restoring journal](#restoring-journal)

* [Journal concept](#journal-concept)

* [Specification for some commands](#specification-for-some-commands)

	* [sync](#sync)

	* [restore](#restore)

	* [restore-completed](#restore-completed)

	* [upload-file](#upload-file)

	* [retrieve-inventory](#retrieve-inventory)

	* [download-inventory](#download-inventory)

	* [list-vaults](#list-vaults)

	* [other commands](#other-commands)

* [File selection options](#file-selection-options)

* [Additional command line options](#additional-command-line-options)

* [Configuring Character Encodings](#configuring-character-encodings)

* [Limitations](#limitations)

* [See also](#see-also)

* [Minimum Amazon Glacier permissions](#minimum-amazon-glacier-permissions)



## Features

* Does not use any existing Amazon Glacier library, so can be flexible in implementing advanced features
* Amazon Glacier Multipart upload
* Multi-segment download (using HTTP Range header)
* Multithreaded upload/download
* Multipart+Multithreaded download/upload
* Multithreaded archive retrieval, deletion and download
* TreeHash validation while downloading
* Tracking of all uploaded files with a local journal file (opened for write in append mode only)
* Checking integrity of local files using journal
* Ability to limit number of archives to retrieve
* File selection options for all commands (using flexible rules with wildcard support)
* Full synchronization to Amazon Glacier - new file uploaded, modified files can be replaced, deletions can be propogated
* File name and modification times are stored as Glacier metadata ([metadata format for developers][mt-aws-glacier Amazon Glacier meta-data format specification])
* Ability to re-create journal file from Amazon Glacier metadata
* Full UTF-8 support (and full single-byte encoding support for *BSD systems)
* Multipart/multithreaded upload from STDIN
* User selectable HTTPS support. Currently defaults to plaintext HTTP
* Vault creation and deletion
* STS/IAM security tokens support

[mt-aws-glacier Amazon Glacier meta-data format specification]:https://github.com/vsespb/mt-aws-glacier/blob/master/lib/App/MtAws/MetaData.pm

## Important bugs/missing features

* Only multipart upload is implemented, no plain upload
* Mac OS X filesystem is treated as case-sensitive

## Production readiness

* After **one year** since first public version released, beta testing was finished and version 1.xxx released. Current project status is **non-beta**, **stable**.

## Installation/System requirements

The script is made for Unix OS. Tested under Linux. Should work under other POSIX OSes (*BSD, Solaris). Lightly tested under Mac OS X.
Will NOT work under Windows/Cygwin. Minimum Perl version required is 5.8.8 (pretty old, AFAIK there are no supported distributions with older Perls)

### Installation via OS package manager

NOTE: If you've used manual installation before, please remove previously installed `mtglacier` executables from your path.

NOTE: If you've used CPAN installation before, please remove previously installed modules, ([cpanm] is able to do that)

##### Ubuntu 12.04+

Can be installed/updated via PPA  [vsespb/mt-aws-glacier](https://launchpad.net/~vsespb/+archive/mt-aws-glacier):

1.	`sudo apt-get update`
2.	`sudo apt-get install software-properties-common python-software-properties`
3.	`sudo add-apt-repository ppa:vsespb/mt-aws-glacier`

	(GPG key id/fingerprint would be **D2BFA5E4** and **D7F1BC2238569FC447A8D8249E86E8B2D2BFA5E4**)

4.	`sudo apt-get update`
5.	`sudo apt-get install libapp-mtaws-perl`

##### Debian 6 (Squeeze)

Can be installed/updated via custom repository

1.	`wget -O - http://mt-aws.com/vsespb.gpg.key | sudo apt-key add -`

	(this will add GPG key 2C00 B003 A56C 5F2A 75C4 4BF8 2A6E 0307 **D0FF 5699**)

2. Add repository


		echo "deb http://dl.mt-aws.com/debian/current squeeze main"|sudo tee /etc/apt/sources.list.d/mt-aws.list


3.	`sudo apt-get update`
4.	`sudo apt-get install libapp-mtaws-perl`


	(To use HTTPS you also need:)

5. `sudo apt-get install build-essential libssl-dev`

6. install/update `LWP::UserAgent` and `LWP::Protocol::https` using [cpanm]

##### Debian 7 (Wheezy), including rasbian for Raspberry Pi

Can be installed/updated via custom repository

1.	`wget -O - https://mt-aws.com/vsespb.gpg.key | sudo apt-key add -`

	(this will add GPG key 2C00 B003 A56C 5F2A 75C4 4BF8 2A6E 0307 **D0FF 5699**)

2. Add repository


		echo "deb http://dl.mt-aws.com/debian/current wheezy main"|sudo tee /etc/apt/sources.list.d/mt-aws.list


3.	`sudo apt-get update`
4.	`sudo apt-get install libapp-mtaws-perl`

##### Debian 8 (Jessie)

Can be installed/updated via custom repository

1.	`wget -O - https://mt-aws.com/vsespb.gpg.key | sudo apt-key add -`

	(this will add GPG key 2C00 B003 A56C 5F2A 75C4 4BF8 2A6E 0307 **D0FF 5699**)

2. Add repository


		echo "deb http://dl.mt-aws.com/debian/current jessie main"|sudo tee /etc/apt/sources.list.d/mt-aws.list


3.	`sudo apt-get update`
4.	`sudo apt-get install libapp-mtaws-perl`

### Manual installation

#### Install prerequisites

###### Ubuntu 12.04+, Debian 7

`sudo apt-get install libwww-perl libjson-xs-perl`

###### RHEL/CentOS 5

1. `sudo yum install perl-Digest-SHA`
2. `sudo yum groupinstall "Development Tools"`
3. `sudo yum install openssl-devel`
4. Install `JSON::XS`, `LWP::UserAgent` and `LWP::Protocol::https` using [cpanm]

You also can install `mtglacier` prerequisites without CPAN if you have [EPEL](http://fedoraproject.org/wiki/EPEL) repository enabled and if you don't need HTTPS:

`sudo yum install perl-Digest-SHA perl-JSON-XS perl-libwww-perl`

###### RHEL/CentOS 6

1. `sudo yum install perl-core perl-CGI`
2. `sudo yum groupinstall "Development Tools"`
3. `sudo yum install openssl-devel`
4. Install `JSON::XS`, `LWP::UserAgent` and `LWP::Protocol::https` using [cpanm]

You also can install `mtglacier` prerequisites without CPAN if you have [EPEL](http://fedoraproject.org/wiki/EPEL) repository enabled and if you don't need HTTPS:

`sudo yum install perl-core perl-CGI perl-JSON-XS perl-libwww-perl`

###### Debian 6

`sudo apt-get install libwww-perl libjson-xs-perl`

To use HTTPS you also need:

1. `sudo apt-get install build-essential libssl-dev`

3. install/update `LWP::UserAgent` and `LWP::Protocol::https` using [cpanm]

###### Fedora 18+

`sudo yum install perl-core perl-CGI perl-JSON-XS perl-libwww-perl perl-LWP-Protocol-https`

###### SUSE Linux Enterprise Server 11

1. `sudo zypper install perl-libwww-perl libopenssl-devel`
2. `sudo zypper install --type pattern Basis-Devel`
3. Upgrade openssl to (at least) `0.9.8r` (to check version use `openssl version`), can be found [here](http://download.opensuse.org/repositories/security:/fips/) (more info here [RT#81575](https://rt.cpan.org/Public/Bug/Display.html?id=81575))
4. Update `ExtUtils::MakeMaker` via [cpanm]
5. Install `LWP::UserAgent`, `LWP::Protocol::https`, `JSON::XS` using [cpanm]

###### Amazon Linux 2013.03

`sudo yum install perl-core perl-JSON-XS perl-libwww-perl perl-LWP-Protocol-https`

###### MacOS X

Install the following packages:

Install `LWP::UserAgent` (`p5-libwww-perl`), `JSON::XS` (`p5-json-XS`). For HTTPS support you need `LWP::Protocol::https`, however on MacOS X
you probably need `Mozilla::CA` (it should go with `LWP::Protocol::https`, but it can be missing). Try to use HTTPS without `Mozilla::CA` - if it does not work, install
`Mozilla::CA`

#### Install mt-aws-glacier

	git clone https://github.com/vsespb/mt-aws-glacier.git

(or just download and unzip `https://github.com/vsespb/mt-aws-glacier/archive/master.zip` )

After that you can execute `mtglacier` script (found in root of repository) from any directory, or create a symlink to it - it will find other package files by itself
(don't forget to remove it later, if you decide to switch to CPAN install)

### *OR* Installation via CPAN

		cpan -i App::MtAws

That's it.


### Installation general instructions, troubleshooting, edge cases and misc instructions

##### In general you need the following perl modules to run *mt-aws-glacier*:

* **LWP::UserAgent** (or Debian package **libwww-perl** or RPM package **perl-libwww-perl** or MacPort **p5-libwww-perl**)
* **JSON::XS** (or Debian package **libjson-xs-perl** or RPM package **perl-JSON-XS** or MacPort **p5-json-XS**)

##### Other notes

1. for old Perl < 5.9.3 (i.e. *CentOS 5.x*), you also need **Digest::SHA** (or Debian package **libdigest-sha-perl** or RPM package **perl-Digest-SHA**)

2. On some distributions with old Perl stuff (examples: *Ubuntu 10.04*, *CentOS 5/6*), to use HTTPS you need to upgrade **LWP::Protocol::https** to version 6+ via CPAN.

3. *Fedora*, *CentOS 6* etc [decoupled](http://www.nntp.perl.org/group/perl.perl5.porters/2009/08/msg149747.html) Perl,
so the package named `perl`, which is a part of default installation, is not actually real, full Perl, which is misleading.
`perl-core` looks much more like a real Perl (I [hope](https://bugzilla.redhat.com/show_bug.cgi?id=985791) so)

4. On newer RHEL distributions (some *Fedora* versions) you need to install **perl-LWP-Protocol-https** to use HTTPS.

5. To inistall `perl-JSON-XS` RPM package on RHEL5/6 you need to enable [EPEL](http://fedoraproject.org/wiki/EPEL) repository

6. If you've used manual installation before "CPAN" installation, it's probably better to remove any previously installed `mtglacier` executable from your path.

7. CPAN distribution of *mt-aws-glacier* has a bit more dependencies than manual installation, as it requires additional modules for the testsuite.

8. New releases of *mt-aws-glacier* usually appear on CPAN within a ~week after official release.

9. On *Fedora*, *CentOS 6 minimal* you need to install `perl-core`, `perl-CPAN`, `perl-CGI` before trying to install via CPAN

10. For some distributions with old Perl stuff (examples: *CentOS 5/6*) you need to update CPAN and Module::Build first: `cpan -i CPAN`, `cpan -i Module::Build`

11. The CPAN tool asks too many questions during install (but ignores important errors). You can avoid it by running the `cpan` command and configuring it like this:

		o conf build_requires_install_policy yes
		o conf prerequisites_policy follow
		o conf halt_on_failure on
		o conf commit
		exit

12. Instead of the system `cpan` tool, you might want to try [`cpanm`](http://search.cpan.org/perldoc?App%3A%3Acpanminus) - it's a bit easier to install and configure.

13. Installation of **LWP::Protocol::https** requires C header files ( `yum groupinstall "Development Tools"` for RHEL or `build-essential` for Debian ) and OpenSSL dev library (`openssl-devel` RPM or `libssl-dev` DEB).

[cpanm]:http://search.cpan.org/perldoc?App%3A%3Acpanminus

## Warnings ( *MUST READ* )

* When playing with Glacier, make sure you will be able to delete all your archives, it's impossible to delete archive
or non-empty vault in amazon console now. Also make sure you have read _all_ Amazon Glacier pricing/faq.

* Read Amazon Glacier pricing [FAQ][Amazon Glacier faq] again, really. Beware of retrieval fee.

* Before using this program, you should read Amazon Glacier documentation and understand, in general, Amazon Glacier workflows and entities. This documentation
does not define any new layer of abstraction over Amazon Glacier entities.

* In general, all Amazon Glacier clients store metadata (filenames, file metadata) in own formats, incompatible with each other. To restore backup made with `mt-aws-glacier` you will
need `mt-aws-glacier`, other software most likely will restore your data but loose filenames.

* With low "partsize" option you pay a bit more (Amazon charges for each upload request)

* For backup created with older versions (0.7x) of mt-aws-glacier, the Journal file is **required to restore backup**.

* Use a given **Journal file** only with a **single vault** ( more info [here](#what-is-journal) and [here](#how-to-maintain-a-relation-between-my-journal-files-and-my-vaults) and [here](https://github.com/vsespb/mt-aws-glacier/issues/50))

* If you work with CD-ROM/CIFS/other non-Unix/non-POSIX filesystems, you might need to set `leaf-optimization` to `0`

* Please read the [ChangeLog][mt-aws glacier changelog] when upgrading to new version, and especially when downgrading.
(See "Compatibility" sections when downgrading)

* Zero length files and empty directories are ignored (as Amazon Glacier does not support it)

* See other [limitations](#limitations)

[Amazon Glacier faq]:http://aws.amazon.com/glacier/faqs/#How_will_I_be_charged_when_retrieving_large_amounts_of_data_from_Amazon_Glacier
[mt-aws glacier changelog]:https://github.com/vsespb/mt-aws-glacier/blob/master/ChangeLog

## Help/contribute this project

* If you like *mt-aws-glacier*, and have a GitHub account, please **Star** it on GitHUb, this way you will help promote the project.
* Please report any bugs or issues (using GitHub issues). Well, any feedback is welcome.
* If you want to contribute to the source code, please contact me first and describe what you want to do

## Usage

1. Create a directory containing files to backup. Example `/data/backup`
2. Create a config file, say, `glacier.cfg`

		key=YOURKEY
		secret=YOURSECRET
		# region: eu-west-1, us-east-1 etc
		region=us-east-1
		# protocol=http (default) or https
		protocol=http

	(you can skip any config option and specify it directly in command line; command line options override the same options in configuration file)
3. Create a vault in specified region, using Amazon Console (`myvault`) or using `mtglacier`

		./mtglacier create-vault myvault --config glacier.cfg

	(note that Amazon Glacier does not return error if vault already exists etc)

4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

		./mtglacier sync --config glacier.cfg --dir /data/backup --vault myvault --journal journal.log --concurrency 3

6. Add more files and sync again
7. Check that your local files were not modified since last sync

		./mtglacier check-local-hash --config glacier.cfg --dir /data/backup --journal journal.log

8. Delete some files from your backup location
9. Initiate an archive restore job on Amazon side

		./mtglacier restore --config glacier.cfg --dir /data/backup --vault myvault --journal journal.log --max-number-of-files 10

10. Wait 4+ hours for Amazon Glacier to complete archive retrieval
11. Download the restored files back to your backup location

		./mtglacier restore-completed --config glacier.cfg --dir /data/backup --vault myvault --journal journal.log

12. Delete all your files from vault

		./mtglacier purge-vault --config glacier.cfg --vault myvault --journal journal.log

13. Wait ~ 24-48 hours and you can try deleting your vault

		./mtglacier delete-vault myvault --config glacier.cfg

	(note: currently Amazon Glacier does not return error if vault is not exists)

## Restoring a journal

In case you lost your journal file, you can restore it from Amazon Glacier metadata

1. Run retrieve-inventory command. This will request Amazon Glacier to prepare the vault inventory.

		./mtglacier retrieve-inventory --config glacier.cfg --vault myvault

2. Wait 4+ hours for Amazon Glacier to complete inventory retrieval (also note that you will get a ~24h old inventory..)

3. Download inventory and export it to the new journal (this sometimes can be pretty slow even if the inventory is small, wait a few minutes):

		./mtglacier download-inventory --config glacier.cfg --vault myvault --new-journal new-journal.log


For files created by mt-aws-glacier version 0.8x and higher, the original filenames will be restored. For other files archive_id will be used as filename. See the Amazon Glacier metadata format for mt-aws-glacier here: [Amazon Glacier metadata format used by mt-aws glacier][Amazon Glacier metadata format used by mt-aws glacier]

[Amazon Glacier metadata format used by mt-aws glacier]:https://github.com/vsespb/mt-aws-glacier/blob/master/lib/App/MtAws/MetaData.pm

## Journal concept

#### What is a Journal

A Journal is a file in your local filesystem, which contains a list of all files uploaded to Amazon Glacier.
Strictly speaking, this file contains a list of operations (list of records), performed with Amazon Glacier vault. The main operations are:
file creation, file deletion and file retrieval.

Create operation records contains: *local filename* (relative to transfer root - `--dir`), file *size*, file last *modification time* (in 1 second resolution), file *TreeHash* (Amazon
hashing algorithm, based on SHA256), file upload time, and Amazon Glacier *archive id*

Delete operation records contains *local filename* and corresponding Amazon Glacier *archive id*

Having such a list of operations, we can, at any time, reconstruct the list of files that are currently stored in Amazon Glacier.

As you see, the Journal records do not contain Amazon Glacier *region*, *vault*, file permissions, last access times and other filesystem metadata.

Thus you should always use a separate Journal file for each Amazon Glacier *vault*. Also, file metadata (except filename and file *modification time*) will
be lost, if you restore files from Amazon Glacier.

#### Some Journal features

* It's a text file. You can parse it with `grep` `awk` `cut`, `tail` etc, to extract information in case you need perform some advanced stuff, that `mtglacier` cannot do (NOTE: make sure you know what you are doing ).

	To view only some files:

		grep Majorca Photos.journal

	To view only creation records:

		grep CREATED Photos.journal | wc -l

	To compare only the important fields of two journals

		cut journal -f 4,5,6,7,8 |sort > journal.cut
		cut new-journal -f 4,5,6,7,8 |sort > new-journal.cut
		diff journal.cut new-journal.cut

* Each text line in a file represents one record

* It's an append-only file. The file is opened in append-only mode, and new records are only added to the end. This guarantees that
you can recover the previous state of a Journal file in case of bug in program/crash/some power/filesystem issues. You can even use `chattr +a` to set append-only protection to the Journal.

* A Journal file is append-only, so it is easy to perform incremental backups of it.

#### Why is Journal a file in the local filesystem, but not stored in the online Cloud (like Amazon S3 or Amazon DynamoDB)?

The Journal is needed to restore a backup, and we can expect that if you need to restore a backup, that means that you lost your filesystem, together with the Journal.

However the Journal is also needed to perform *new backups* (`sync` command), to determine which files are already in Glacier and which are not. And also to check local file integrity (`check-local-hash` command).
Usually you perform new backups every day. And you restore backups (and loose your filesystem) very rarely.

So a fast (local) Journal is essential to perform new backups fast and cheap (important for users who backup thousands or millions of files).

And if you lost your Journal, you can restore it from Amazon Glacier (see `retrieve-inventory` command). Also it's recommended to backup your Journal
to another backup system (Amazon S3 ? Dropbox ?) with another tool, because retrieving the inventory from Amazon Glacier is pretty slow.

Also some users might want to backup the *same* files from *multiple* different locations. They will need *synchronization* solution for journal files.

Anyway I think the problem of putting Journals into the cloud can be automated and solved with 3 lines bash script..

#### How to maintain a relation between my journal files and my vaults?

1. You can name the Journal with same name as your vault. Example: Vault name is `Photos`. Journal file name is `Photos.journal`. Or `eu-west-1-Photos.journal`

2. (Almost) Any command line option can be used in the config file, so you can create `myphotos.cfg` with following content:

		key=YOURKEY
		secret=YOURSECRET
		protocol=http
		region=us-east-1
		vault=Photos
		journal=/home/me/.glacier/photos.journal

#### Why does Journal not contain region/vault information?

Keeping journal/vault in config looks more like the Unix way to me. It can be a bit dangerous, but easier to maintain, because:

1. Let's imagine I decided to put region/vault into the Journal. There are two options:

	a. Put it into beginning of the file, before journal creation.

	b. Store same region/vault in each record of the file. It looks like a waste of disk space.

	Option (a) looks better. So this way journal will contain something like

		region=us-east-1
		vault=Photos

	in the beginning. But same can be achieved by putting same lines to the config file (see previous question).

2. Also, putting vault/region into the Journal will make command line options `--vault` and `--region` useless
for general commands and will require to add another command (something like `create-journal-file`).

3. There is a possibility to use different *account id* in Amazon Glacier (i.e. different person's account). It's not supported yet in `mtglacier`,
but when it will, I will have to store *account id* together with *region*/*vault*. Also, the default *account id* is `-` (means 'my account'). If one wish to use same
vault from a different Amazon Glacier account, one has to change `-` to a real account id. So we need the ability to edit *account id*.
And *region/vault* information does not make sense without this account id.

4. Some users can have different permissions for different vaults, so
they need to maintain the relation between
`key`, `secret`, `account_id`, `region/vault`, `journal` in the same place
(this can only be a config file, because involves `secret`).

5. Amazon might allow renaming vaults or moving them across regions, in the future.

6. Currently a Journal consists of independent records, so it can be split to separate records using `grep`, or several
journals can be merged using `cat` (but be careful if doing that).

7. In the future, there can be other features and options added, such as compression/encryption, which might require to decide again where to put new attributes for them.

8. Usually there is different policy for backing up config files and Journal files (modifiable). So if you loose your journal file, you won't be sure which config corresponds to which *vault* (and a Journal file can be restored from a *vault*).

9. It's better to keep relation between *vault* and transfer root (`--dir` option) in one place, such as a config file.

#### Why does Journal (and metadata stored in Amazon Glacier) not contain file's metadata (like permissions)?

If you want to store permissions, put your files into archives before backup to Amazon Glacier. There are lots of different possible things to store as file metadata information,
most of them are not portable. Take a look at various archives file formats - different formats allows to store different metadata.

It's possible that in the future `mtglacier` will support some other metadata.

## Specification for some commands

### `sync`

Propagates current local filesystem state to Amazon Glacier server.

`sync` accepts one or several of the following mode options: `--new`, `--replace-modified`, `--delete-removed`

If none of three above mode options are provided, `--new` is implied (basically for backward compatibility).

1. `--new`

	Uploads the files which exist in local filesystem (and have non-zero size) but do not exist in Amazon Glacier (i.e., in Journal)

2. `--replace-modified`

	Uploads modified files (i.e., which exist in local filesystem and in Amazon Glacier). After a file is successfully uploaded,
	the previous version of the file is deleted from Amazon Glacier. The logic of detection of modified files is controlled by `--detect` option.

3. `--delete-removed`

	Deletes the files from Amazon Glacier which missing in the local filesystem (or have zero size).

4. `--detect`

	Controls how `--replace-modified` detects modified files. Possible values are: `treehash`, `mtime`, `mtime-or-treehash`, `mtime-and-treehash`,
	`always-positive`, `size-only`.
	Default value is `mtime-and-treehash`

	A file is always considered modified if its *size changed* (but not zero)

	 1. `treehash` - calculates the TreeHash checksum for a file and compares with the checksum in Journal. If the checksums do not match, the file is considered modified.

	 2. `mtime` - compares last modification time in local filesystem and in journal, if it differs, the file is considered modified.

	 3. `mtime-or-treehash` - compares file last modification time, if it differs, the file is considered modified. If it matches - compares TreeHash.

	 4. `mtime-and-treehash` - compares file last modification time, if it differs - compares TreeHash. If the modification time is the same, the file
	 considered not-modified, and the TreeHash not checked.

	 5. `always-positive` - always treat files as modified -- modification time and TreeHash are ignored. This option probably makes sense only when combined with the `--filter` options.

	 6. `size-only` - consider a file as modified only if the sizes differ.

	NOTE: the default mode for detection is `mtime-and-treehash`. This is good for performance (treehash checked only for files with modification time changed),
	but `mtime-or-treehash` and `treehash` are more safe in case you are not sure which programs change your files and how.

	NOTE: `mtime-or-treehash` is a mnemonic for *File is modified if mtime differs OR treehash differs*
	`mtime-and-treehash` is a mnemonic for *File is modified if mtime differs AND treehash differs*. The words
	*AND* and *OR* here refer to the logical operators with [short-circuit evaluation](http://en.wikipedia.org/wiki/Short-circuit_evaluation).
	For example, with `mtime-and-treehash`, the TreeHash are never checked if the mtime do not differ. And with `mtime-or-treehash` the TreeHash are never checked if the mtime differ.

NOTE: files with zero size are not supported by Amazon Glacier API, thus considered non-existing for consistency, for all `sync` modes.

NOTE: `sync` does not upload empty directories, there is no such thing as a directory in Amazon Glacier.

NOTE: With the `--dry-run` option, the TreeHash will not be calculated, instead the *Will VERIFY treehash and upload...* message will be displayed.

NOTE: TreeHash calculation is performed in parallel, so some of workers (defined with `--concurrency`) might be busy calculating treehash instead
of network IO.

### `restore`

Initiate Amazon Glacier RETRIEVE operation for files listed in the Journal which do not *exist* on the local filesystem and for
which RETRIEVE was not initiated during the last 24 hours (that information is obtained from *Journal* too - each retrieval is logged
into journal together with timestamp).

### `restore-completed`

Donwloads the files listed in Journal which don't *exist* on the local filesystem, and which were previously
RETRIEVED (using `restore` command) and now available for download (i.e. in about ~4 hours after `restore`).
Unlike `restore` command, the list of retrieved files is requested from the Amazon Glacier servers at runtime using their API, not from the Journal.

The data is downloaded to unique temporary files (created in same directory as the destination file). Those temporary files are renamed to real files
only when the download finishes successfully. In case the program terminates with an error or after Ctrl-C, the temporary files with unfinished
downloads are removed.

If `segment-size` is specified (greater than 0) and particular the file size in megabytes is larger than `segment-size`,
the download of this file is performed in multiple segments, i.e., using HTTP `Range:` header (each of size `segment-size` MiB, except the last,
which can be smaller). Segments are downloaded in parallel (and different segments from different files can
be downloaded at the same time).

Only values that are power of two supported for `segment-size` currently.

Currenly if the download breaks due to network problems, no resumption is performed, the download of file or of current segment
will need to restart from beginning.

In case of multi-segment downloads, the TreeHash reported by Amazon Glacier for each segment is compared with actual TreeHash, calculated for each segment at runtime.
In case of a mismatch, an error is thrown and the process is stopped. The final TreeHash for the whole file is not checked yet.

In case of full-file downloads, the TreeHash reported by Amazon Glacier for the whole file is compared with the one calculated at runtime and with the one found in the Journal. In case of a mismatch, an error is thrown and the process is stopped.

Unlike the `partsize` option, `segment-size` does not allocate buffers of the specified size in memory, so you can use large `segment-size` values.

### `upload-file`

Uploads a single file into Amazon Glacier. The file will be tracked in the Journal (just like when using the `sync` command).

There are several possible combinations of options for `upload-file`:

1. **--filename** and **--dir**

	_Uploads what_: a file, pointed by `filename`.

	_Filename in Journal and Amazon Glacier metadata_: A relative path from `dir` to `filename`

		./mtglacier upload-file --config glacier.cfg --vault myvault --journal journal.log --dir /data/backup --filename /data/backup/dir1/myfile

	(this will upload content of `/data/backup/dir1/myfile` to Amazon Glacier and use `dir1/myfile` as filename for Journal )

		./mtglacier upload-file --config glacier.cfg --vault myvault --journal journal.log --dir data/backup --filename data/backup/dir1/myfile

	(Let's assume current directory is `/home`. Then this will upload content of `/home/data/backup/dir1/myfile` to Amazon Glacier and use `dir1/myfile` as filename for Journal)

	NOTE: the file `filename` should be inside the directory `dir`

	NOTE: both `--filename` and `--dir` are resolved to full paths before determining the relative path from `--dir` to `--filename`. Thus, you will get an error
	if the parent directories are unreadable. Also, if you have a `/dir/ds` symlink to a `/dir/d3` directory, then `--dir /dir` `--filename /dir/ds/file` will result in relative filename `d3/file` not `ds/file`

2. **--filename** and  **--set-rel-filename**

	_Uploads what_: a file, pointed by `filename`.

	_Filename in Journal and Amazon Glacier metadata_: As specified in `set-rel-filename`

		./mtglacier upload-file --config glacier.cfg --vault myvault --journal journal.log --filename /tmp/myfile --set-rel-filename a/b/c

	(this will upload the content of `/tmp/myfile` to Amazon Glacier and use `a/b/c` as the filename in the Journal.)

	(NOTE: `set-rel-filename` should be a _relative_ filename, it must not start with `/`)

3. **--stdin**, **--set-rel-filename** and **--check-max-file-size**

	_Uploads what_: a file, read from STDIN

	_Filename in Journal and Amazon Glacier metadata_: As specified in `set-rel-filename`

	Also, as file size is not known until the very end of the upload, you need to be sure that file will not exceed the 10,000 parts limit, and you must
	specify `check-max-file-size` -- the maximum possible size of file (in Megabytes), that you can expect. What this option does is simply to throw an error
	if `check-max-file-size`/`partsize` > 10 000 parts (in that case it's recommended to adjust `partsize`). That's all. I remind you that you can put this (and
	any other option) in the config file


		./mtglacier upload-file --config glacier.cfg --vault myvault --journal journal.log --stdin --set-rel-filename path/to/file --check-max-file-size 131

	(this will upload the content of the file read from STDIN to Amazon Glacier and use `path/to/file` as filename in the Journal.)

	(NOTE: `set-rel-filename` should be a _relative_ filename i.e. must not start with `/`)


NOTES:

1. In the current version of mtglacier you are not allowed to store multiple versions of same file, that is, to upload multiple files with the same relative filename
to a single Amazon Glacier vault and single Journal. Simple file versioning will be implemented in the future versions.

2. You can use other optional options with this command (`concurrency`, `partsize`).

### `retrieve-inventory`

Issues inventory retrieval request for `--vault`.

You can specify the inventory format with `--request-inventory-format`. Allowed values are `json` and `csv`. Defaults to `json`.
Note that it is not recommended to use `csv` unless you have to: Amazon CSV format is not documented, has bugs and the `mt-aws-glacier` CSV parsing
implementation (i.e. `download-inventory` command) is about 10 times slower than JSON.

See also [Restoring journal](#restoring-journal) for `retrieve-inventory`, `download-inventory` commands examples.

### `download-inventory`

Parses Amazon glacier job list (for `--vault`) taken from Amazon servers at runtime, finds the latest (by initiation date) inventory retrieval request,
downloads it, converts it to a Journal file and saves it to `--new-journal`. Both `CSV` and `JSON` jobs are supported.

See also [Restoring journal](#restoring-journal) for `retrieve-inventory`, `download-inventory` commands examples.

### `list-vaults`

Lists all vaults in region specified by `--region` (with a respect to IAM permissions for listing vaults), printing them to the screen. The default format is human readable, not for parsing. Use `--format=mtmsg` for a machine readable tab-separated format (which is not yet documented here, however it's self-explanatory and backward compatability is guaranteed; one note: LastInventoryDate can be the empty string as Amazon API can return it as null).

### Other commands

See [usage](#usage) for examples of use of the following commands: `purge-vault`, `check-local-hash`, `create-vault`, `delete-vault`.

## File selection options

The `filter`, `include` and `exclude` options allow you to construct a list of RULES to select only certain files for the operation.
Can be used with commands: `sync`, `purge-vault`, `restore`, `restore-completed ` and `check-local-hash`

+ **--filter**

	Adds one or several RULES to the list of rules. One filter value can contain multiple rules, it has same effect as multiple filter values with one
	RULE each.

		--filter 'RULE1 RULE2' --filter 'RULE3'

	is the same as

		--filter 'RULE1 RULE2 RULE3'


	RULES should be a sequence of PATTERNS, followed by '+' or '-' and separated by spaces. There can be a space between '+'/'-' and PATTERN.

		RULES: [+-]PATTERN [+-]PATTERN ...


	'+' means INCLUDE PATTERN, '-' means EXCLUDE PATTERN


	NOTES:

		1. If RULES contain spaces or wildcards, you must quote them together when running `mtglacier` from Shell (Example: `mtglacier ... --filter -tmp/` but `mtglacier --filter '-log/ -tmp/'`)


		2. Although PATTERN in principle can contain spaces, you cannot use them here, because the RULES are separated by spaces.


		3. PATTERN can be empty (Example: `--filter +data/ --filter -` - excludes everything except any directory with name `data`, last pattern is empty)


		4. Unlike other options, `filter`, `include` and `exclude` cannot be used in a config file (in order to avoid mess with order of rules)


+ **--include**

	Adds an INCLUDE PATTERN to the list of rules (Example: `--include /data/ --filter '+/photos/ -'` - include only photos and data directories)

+ **--exclude**

	Adds an EXCLUDE PATTERN to the list of rules (Example: `--exclude /data/` - include everything except /data and subdirectories)

	NOTES:

		1. You can use spaces in the PATTERNS here (Example: `--exclude '/my documents/'` - include everything except "/my documents" and subdirectories)


+ **How PATTERNS work**

+ 1)  If a pattern starts with a '/' then it is anchored to a particular spot in the hierarchy of files, otherwise it is matched against the final
component of the filename.

		`/tmp/myfile` - matches only `/tmp/myfile`. But `tmp/myfile` - matches `/tmp/myfile` and `/home/john/tmp/myfile`

+ 2) If a pattern ends with a '/' then it will only match a directory and all files/subdirectories inside this directory. It won't match a regular file.
Note that if the directory is empty, it won't be synchronized to Amazon Glacier, as it does not support directories.

		`log/` - matches only directory `log`, but not a file `log`

+ 3) If a pattern does not end with a '/', it won't match a directory (directories are not supported by Amazon Glacier, so it makes no sense to match a directory
without subdirectories). However if, in future versions, we find a way to store empty directories in Amazon Glacier, this behavior may change.

		`log` - matches only file `log`, but not a directory `log` nor files inside it

+ 4) if a pattern contains a '/' (not counting a trailing '/') then it is matched against the full pathname, including any leading directories.
Otherwise it is matched only against the final component of the filename.

		`myfile` - matches `myfile` in any directory (i.e. matches both `/home/ivan/myfile` and `/data/tmp/myfile`), but it does not match
		`/tmp/myfile/myfile1`. While `tmp/myfile` matches `/data/tmp/myfile` and `/tmp/myfile/myfile1`

+ 5) The wildcard '*' matches zero or more characters, but it stops at slashes.

		`/tmp*/file` matches `/tmp/file`, `/tmp1/file`, `/tmp2/file` but not `tmp1/x/file`

+ 6) The wildcard '**' matches anything, including slashes.

		`/tmp**/file` matches `/tmp/file`, `/tmp1/file`, `/tmp2/file`, `tmp1/x/file` and `tmp1/x/y/z/file`

+ 7) When the wildcard '**' is meant to be a separated path component (i.e. surrounded with slashes/beginning of line/end of line), it matches 0 or more subdirectories.

		`/foo/**/bar` matches `foo/bar` and `foo/x/bar`. Also `**/file` matches `/file` and `x/file`

+ 8) The wildcard '?' matches any (exactly one) character except a slash ('/').

		`??.txt` matches `11.txt`, `xy.txt` but not `abc.txt`

+ 9) if PATTERN is empty, it matches anything.

		`mtglacier ... --filter '+data/ -'` - Last pattern is empty string (followed by '-')

+ 10) If PATTERN is started with '!' it only match when rest of the pattern (the pattern without '!') does not match.

		`mtglacier ... --filter '-!/data/ +*.gz' -` - include only `*.gz` files inside `data/` directory.

+ **How rules are processed**

+ 1) The relative filename of each file (relative to `--dir` root) is checked against rules in the list. Once a filename matches a PATTERN, the file is included or excluded depending on the kind of PATTERN matched.
No other rule is checked after first match.

		`--filter '+*.txt -file.txt'` File `file.txt` is INCLUDED, it matches 1st pattern, so 2nd pattern is ignored

+ 2) If no rule matched, the file is included (default rule is INCLUDE rule).

		`--filter '+*.jpeg'` File `file.txt` is INCLUDED, as it does not match any rules

+ 3) When we process both local files and Journal filelist (sync, restore commands), the rules are applied to BOTH sides.

+ 4) When we traverse a directory tree, (in contrast to behavior of some tools, like _Rsync_), if a directory (and all subdirectories) match an exclude pattern,
the directory tree is not pruned, the traversal goes into the directory. So this will work fine (it will include `/tmp/data/a/b/c`, but exclude all other files in `/tmp/data`):

		--filter '+/tmp/data/a/b/c -/tmp/data/ +'

+ 5) In some cases, to reduce disk IO, the traversal of an excluded directory can be stopped.
This only can happen when `mtglacier` is absolutely sure that it will not break behavior (4) described above.
Currently it's guaranteed that traversal stop only in the cases where:

+ A directory match EXCLUDE rule without '!' prefix, ending with '/' or '**', or empty rule

+ AND there are no INCLUDE rules before this EXCLUDE RULE

		`--filter '-*.tmp -/media/ -/proc/ +*.jpeg'` - system '/proc' and huge '/media' directory is not traversed.

+ 6) Non-ASCII characters in PATTERNS are supported.

## Additional command line options

NOTE: Any command line option can be used in the config file as well, but options specified on command line override options specified in config.

1. `concurrency` (with `sync`, `upload-file`, `restore`, `restore-completed` commands) - number of parallel upload streams to run. (default 4)

		--concurrency 4

2. `partsize` (with `sync`, `upload-file` command) - size of file chunk to upload at once, in Megabytes. (default 16)

		--partsize 16

3. `segment-size` (with `restore-completed` command) - size of download segment, in MiB  (default: none)

	If `segment-size` is specified (greater than zero), and file size in megabytes is larger than `segment-size`, the download is performed in
	multiple segments.

	If it is omited or zero, multi-segment download is disabled (this is the default)

	`segment-size` should be power of two.

4. `max-number-of-files` (with `sync` or `restore` commands) - limit number of files to sync/restore. The program will finish when this limit is reached.

		--max-number-of-files 100

5. `key/secret/region/vault/protocol` - you can override any option from the config file

6. `dry-run` (with `sync`, `purge-vault`, `restore`, `restore-completed ` and even `check-local-hash` commands) - do not perform actual work, print what will happen instead.

		--dry-run

6. `leaf-optimization` (only valid with the `sync` command). `0` - disable. `1` - enable (default).
Similar to the `-noleaf` option of [find][find] (coreutils tools) and the `$dont_use_nlink` option of [File::Find][File::Find].
When disabled, the number of hardlinks to a directory is ignored during file tree traversal. This slow down file search, but it is more
compatible with (some) CIFS/CD-ROM filesystems.
For more information see the manuals of [find][find] and [File::Find][File::Find].

7. `token` (valid for all commands which connect Amazon Glacier API) - a STS/IAM security token, described in [Amazon STS/IAM Using Temporary Security Credentials to Access AWS]

[Amazon STS/IAM Using Temporary Security Credentials to Access AWS]:http://docs.aws.amazon.com/STS/latest/UsingSTS/UsingTokens.html
[find]:http://unixhelp.ed.ac.uk/CGI/man-cgi?find
[File::Find]:http://search.cpan.org/perldoc?File%3A%3AFind

8. `timeout` (valid for all commands which connect Amazon Glacier API)

	Sets the timeout value in seconds -- the default value is 180 seconds. Each request to Amazon Glacier is retried if no activity
	on the connection to the server is observed for `timeout` seconds. This means that the total time taken by the whole
	request might be longer.

9. `follow` (only `sync` command)

	Follow symbolic links during directory traversal. This option decreases performance and increases memory usage. Similar to `find -L`

## Configuring Character Encodings

The autodetection of locale/encodings is not implemented yet, but currently there is the ability to tune encodings manually.

Below are 4 options that can be used in the config file and on the command line.

1. `terminal-encoding` - Encoding of your terminal (STDOUT/STDERR for system messages)

2. `filenames-encoding` - Encoding of filenames in filesystem.

	Under most *nix filesystems, filenames are stored as byte sequences, not characters. So in theory the applications are responsible of managing the encoding.

3. `config-encoding` - Encoding of your config file (`glacier.cfg` in examples above)

4. `journal-encoding` - Encoding to be used for the Journal file (when reading and writing Journal files specified with the `--journal` and `--new-journal` options)


The default value for all options is 'UTF-8'. Under Linux and Mac OS X you usually don't need to change encodings.
Under *BSD systems, single-byte encodings are often used. You will most probably need to change `terminal-encoding` and `filenames-encoding`. Optionaly you can also
change `config-encoding` and `journal-encoding`.

Notes:

* Before changing `config-encoding` and `journal-encoding`, you are responsible for transcoding file content of config and journal files manually.

* You are responsible for encoding compatibility. For example, do not try to work with UTF-8 journal with non-Cyrilic characters and KOI8-R (Cyrilic) filesystem.

* Do not try to use UTF-16 for *nix filesystem. It's not ASCII compatible and contains `\x00` bytes, which cannot be stored in filesystem.

* Do not use `UTF8` - it does not validate data, use `UTF-8` (one with a dash) instead.

* To get the list of encodings installed with your Perl run:

		perl -MEncode -e 'print join qq{\n}, Encode->encodings(q{:all})'

* The config file name (specified with `--config`) can be in any encoding (it's used as is). Of course it will work only if your terminal encoding matches your
filesystem encoding or if your config file name consists of ASCII-7bit characters only.

* Additional information about encoding support in Perl programming language: [CPAN module Encode::Supported](http://search.cpan.org/perldoc?Encode%3A%3ASupported)

* Amazon Glacier metadata (on Amazon servers) is always stored in UTF-8. There is no way to override it. You can use a Journal in any encoding with the same
metadata without problems and you can dump metadata to journals with different encodings (using `download-inventory` command).

* See also [convmv tool](http://www.j3e.de/linux/convmv/man/)

## Limitations

* Only support filenames which consist of octets that can be mapped to a valid character sequence in desired encoding. Filenames
which are made of random bytes/garbage are not supported. Usually it's not a problem.

* Filenames with CR (Carriage return, code 0x0D) LF (Line feed, code 0x0A) and TAB (0x09) are not supported (usually not a problem too).

* Length of relative filenames is currently limited to about 700 ASCII characters or 350 2-byte UTF-8 character (.. or 230 3-byte characters).

* The file modification time should be in the range from year 1000 to year 9999.

(NOTE: if above requirements are not met, an error will be thrown)

* If you uploaded files with file modifications dates past Y2038 on system which supports it, and then restored them on a system
which does not (like Linux 32bit), the resulting file timestamp will (of course) be wrong and also
unpredictible (undefined behaviour). The only thing that is guaranteed is that if you restore a Journal from Amazon servers on affected (i.e. 32bit)
machine, the Journal will contain correct timestamps (same as on 64bit).

* The approximate formula for memory usage (for 'sync') `min(NUMBER_OF_FILES_TO_SYNC, max-number-of-files) + partsize*concurrency`

* With high `partsize*concurrency` values there is a risk of getting network timeouts -- HTTP 408/500.


## Test/Play with it

1. create an empty dir MYDIR
2. Set the vault name inside `cycletest.sh`
3. Run

		./cycletest.sh init MYDIR
		./cycletest.sh retrieve MYDIR
		./cycletest.sh restore MYDIR

* OR

		./cycletest.sh init MYDIR
		./cycletest.sh purge MYDIR

## See also

* Amazon Glacier Perl library on CPAN - see [Net::Amazon::Glacier][Amazon Glacier API CPAN module - Net::Amazon::Glacier] by *Tim Nordenfur*
* Amazon Glacier TreeHash CPAN module [Net::Amazon::TreeHash][Amazon Glacier TreeHash CPAN module - Net::Amazon::TreeHash] (copied from `mtglacier` code)
* [Amazon Glacier development forum][Amazon Glacier development forum]

[Amazon Glacier API CPAN module - Net::Amazon::Glacier]:https://metacpan.org/module/Net::Amazon::Glacier
[Amazon Glacier TreeHash CPAN module - Net::Amazon::TreeHash]:https://metacpan.org/module/Net::Amazon::TreeHash
[Amazon Glacier development forum]:https://forums.aws.amazon.com/forum.jspa?forumID=140


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
			  "glacier:DeleteVault", "glacier:ListVaults"]
		}
		]
	}


#### EOF

[![mt-aws glacier tracking pixel](https://mt-aws.com/mt-aws-glacier-transp.gif "mt-aws glacier tracking pixel")](http://mt-aws.com/)
