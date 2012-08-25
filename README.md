mt-aws-glacier
==============
Perl Multithreaded multipart sync to Amazon AWS Glacier service.

## Intro

Amazon AWS Glacier is an archive/backup service with very low storage price. However with some caveats in usage and archive retrieval prices.
[Read more about Amazon AWS Glacier](http://aws.amazon.com/glacier/) 

mt-aws-glacier is a client application	 for Glacier.

## Features

* Glacier Multipart upload
* Multithreaded upload
* Multipart+Multithreaded upload
* Multithreaded retrieval, deletion and download
* Tracking of all uploaded files with a local journal file (opened in append mode only)
* Checking integrity of local files
* Ability to limit number of archives to retrieve

## Coming-soon features

* Multipart download (using HTTP Range header)
* Ability to limit number of archives to retrieve, by size, by traffic/hour
* Use journal file as flock() mutex
* Checking integrity of remote files
* Upload from STDOUT
* Some integration with external world, ability to read SNS topics

## Planed next version features

* Amazon S3 support

## Important bugs/missed features

* chunk size hardcoded as 2MB
* number of children hardcoded
* Retrieval works as proof-of-concept, so you can't initiate retrieve job twice (until previous job is completed)
* No way to specify SNS topic 


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

		./cycletest.sh init MYDIR
		./cycletest.sh retrieve MYDIR
		./cycletest.sh restore MYDIR

OR

		./cycletest.sh init MYDIR
		./cycletest.sh purge MYDIR
