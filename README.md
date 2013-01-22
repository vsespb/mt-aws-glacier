mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon Glacier service.

## Intro

Amazon Glacier is an archive/backup service with very low storage price. However with some caveats in usage and archive retrieval prices.
[Read more about Amazon Glacier][amazon glacier] 

mt-aws-glacier is a client application for Glacier.

[amazon glacier]:http://aws.amazon.com/glacier/

## Version

* Version 0.83 beta (See [ChangeLog][mt-aws glacier changelog])

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
* File name and modification times are stored as Glacier metadata
* Ability to re-create journal file from Amazon Glacier metadata
* UTF-8 support
* User selectable HTTPS support. Currently defaults to plaintext HTTP

## Coming-soon features

* Multipart download (using HTTP Range header)
* Use journal file as flock() mutex
* Checking integrity of remote files
* Upload from STDIN
* Some integration with external world, ability to read SNS topics
* Simplified distribution for Debian/RedHat
* Split code to re-usable modules, publishing on CPAN (Currently there are great existing Glacier modules on CPAN - see [Net::Amazon::Glacier][Amazon Glacier API CPAN module - Net::Amazon::Glacier] by *Tim Nordenfur*) 
* Create/Delete vault functions


[Amazon Glacier API CPAN module - Net::Amazon::Glacier]:https://metacpan.org/module/Net::Amazon::Glacier 

## Planned next version features

* Amazon S3 support

## Important bugs/missed features

* Zero length files are ignored
* Only multipart upload implemented, no plain upload
* Mac OS X filesystem treated as case-insensetive

## Production ready

* Not recommended to use in production until first "Release" version. Currently Beta.

## Installation/System requirements

Script is made for Linux OS. Tested under Ubuntu and Debian. Should work under other Linux distributions. Lightly tested under Mac OS X.
Should NOT work under Windows. 

* Install the following CPAN modules:

	* **LWP::UserAgent** (or Debian package **libwww-perl** or RPM package **perl-libwww-perl** or MacPort **p5-libwww-perl**)
	* **JSON::XS** (or Debian package **libjson-xs-perl** or RPM package **perl-JSON-XS** or MacPort **p5-json-XS**)

	* for Perl < 5.9.3 (i.e. CentOS 5.x), install also **Digest::SHA** (or Debian package **libdigest-sha-perl** or RPM package **perl-Digest-SHA**)
	* to use HTTPS install LWP::UserAgent::https (or Debian package **libcrypt-ssleay-perl** or RPM package **perl-Crypt-SSLeay** or MacPort **p5-lwp-protocol-https**)
		
* Install mt-aws-glacier

		git clone https://github.com/vsespb/mt-aws-glacier.git

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

3. Create a vault in specified region, using Amazon Console (`myvault`)
4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

		./mtglacier.pl sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --concurrency=3

6. Add more files and sync again
7. Check that your local files not modified since last sync

		./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
8. Delete some files from your backup location
9. Initiate archive restore job on Amazon side

		./mtglacier.pl restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log --max-number-of-files=10

10. Wait 4+ hours for Amazon Glacier to complete archive retrieval
11. Download restored files back to backup location

		./mtglacier.pl restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log

12. Delete all your files from vault

		./mtglacier.pl purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault --journal=journal.log

## Restoring journal

In case you lost your journal file, you can restore it from Amazon Glacier metadata

1. Run retrieve-inventory command. This will request Amazon Glacier to prepare vault inventory.

		./mtglacier.pl retrieve-inventory --config=glacier.cfg --vault=myvault

2. Wait 4+ hours for Amazon Glacier to complete inventory retrieval (also note that you will get only ~24h old inventory..)

3. Download inventory and export it to new journal (this sometimes can be pretty slow even if inventory is small, wait a few minutes):

		./mtglacier.pl download-inventory --config=glacier.cfg --vault=myvault --new-journal=new-journal.log


For files created by mt-aws-glacier version 0.8x and higher original filenames will be restored. For other files archive_id will be used as filename. See Amazon Glacier metadata format for mt-aws-glacier here: [Amazon Glacier metadata format used by mt-aws glacier][Amazon Glacier metadata format used by mt-aws glacier]

[Amazon Glacier metadata format used by mt-aws glacier]:https://github.com/vsespb/mt-aws-glacier/blob/86031708866c7b444b6f8efa4900f42536c91c5a/MetaData.pm#L35

## Additional command line options

1. "concurrency" (with 'sync' command) - number of parallel upload streams to run. (default 4)

		--concurrency=4

2. "partsize" (with 'sync' command) - size of file chunk to upload at once, in Megabytes. (default 16)

		--partsize=16

3. "max-number-of-files" (with 'sync' or 'restore' commands) - limit number of files to sync/restore. Program will finish when reach this limit.

		--max-number-of-files=100

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

Something like this:

		{
		"Statement": [
			{
			"Effect": "Allow",
			"Resource":["arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test1",
				"arn:aws:glacier:us-east-1:XXXXXXXXXXXX:vaults/test1",
				"arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test2",
				"arn:aws:glacier:eu-west-1:XXXXXXXXXXXX:vaults/test3"],
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
			}
			]
		}

#### EOF

[![mt-aws glacier tracking pixel](https://mt-aws.com/mt-aws-glacier-transp.gif "mt-aws glacier tracking pixel")](http://mt-aws.com/)

