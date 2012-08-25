mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon AWS Glacier service.

## Intro

Amazon AWS Glacier is an archive/backup service with very low storage price. However with some caveats in usage and archive retrieval prices.
[Read more about Amazon AWS Glacier](http://aws.amazon.com/glacier/) 

mt-aws-glacier is a client application	 for Glacier.

## Features

* Does not use any existing AWS library, so can be flexible in implementing advanced features
* Glacier Multipart upload
* Multithreaded upload
* Multipart+Multithreaded upload
* Multithreaded retrieval, deletion and download
* Tracking of all uploaded files with a local journal file (opened in append mode only)
* Checking integrity of local files using journal
* Ability to limit number of archives to retrieve

## Coming-soon features

* Multipart download (using HTTP Range header)
* Ability to limit amount of archives to retrieve, by size, or by traffic/hour
* Use journal file as flock() mutex
* Checking integrity of remote files
* Upload from STDOUT
* Some integration with external world, ability to read SNS topics
* Simplified distribution for Debian/RedHat
* Split code to re-usable modules, publish on CPAN
* Create/Delete vault function

## Planed next version features

* Amazon S3 support

## Important bugs/missed features

* chunk size hardcoded as 2MB
* Only multipart upload implemented, no plain upload
* number of children hardcoded
* Retrieval works as proof-of-concept, so you can't initiate retrieve job twice (until previous job is completed)
* No way to specify SNS topic 
* HTTP only, no way to configure HTTPS yet (however it works fine in HTTPS mode)
* Internal refractoring needed, no comments in source yet, unit tests not published


## Installation

* Install the following CPAN modules:

				LWP::UserAgent JSON::XS
		
that's all

* in case you use HTTPS, also install

				LWP::Protocol::https
		
* Some CPAN modules better install as OS packages (example for Ubuntu/Debian)
				
				libjson-xs-perl liblwp-protocol-https-perl liburi-perl

## Warning

* When playing with Glacier make sure you will be able to delete all your archives, it's impossible to delete archive
or non-empty vault in amazon console now. Also make sure you have read _all_ AWS Glacier pricing/faq.

* Read their pricing FAQ again, really. Beware of retrieval fee.

## Usage
 
1. Create a directory containing files to backup. Example `/data/backup`
2. Create config file, say, glacier.cfg

				key=YOURKEY                                                                                                                                                                                                                                                      
				secret=YOURSECRET                                                                                                                                                                                                                               
				region=us-east-1 #eu-west-1, us-east-1 etc

3. Create a vault in specified region, using Amazon Console (`myvault`)
4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

				./mtglacier.pl sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
6. Add more files and sync again
7. Check that your local files not modified since last sync

				./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
8. Delete some files from your backup location
9. Initiate archive restore job on Amazon side

				./mtglacier.pl restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log --max-number-of-files=10
    
10. Wait 4+ hours
11. Download restored files back to backup location

				./mtglacier.pl restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
12. Delete all your files from vault

				./mtglacier.pl purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log

## Test/Play with it

1. create empty dir MYDIR
2. Watch the source of `cycletest.sh`
3. Run

		./cycletest.sh init MYDIR
		./cycletest.sh retrieve MYDIR
		./cycletest.sh restore MYDIR

OR

		./cycletest.sh init MYDIR
		./cycletest.sh purge MYDIR
		
		
## Minimum AWS permissions

something like that

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


 
