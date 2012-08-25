mt-aws-glacier
==============

Perl Multithreaded multipart sync to Amazon AWS Glacier service

# Usage

1. Create a directory containing files to backup. Example `/data/backup`
2. Create config file, say, glacier.cfg

				key=YOURKEY                                                                                                                                                                                                                                                      
				secret=YOURSECRET                                                                                                                                                                                                                               
				region=us-east-1 #eu-west-1, us-east-1 etc

5. Create a vault in specified region, using Amazon Console (`myvault`)
4. Choose a filename for the Journal, for example, `journal.log`
5. Sync your files

				./mtglacier.pl sync --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
6. Check that your local files not modified since last sync

				./mtglacier.pl check-local-hash --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
7. Delete some files from your backup location
8. Initiate archive restore job on Amazon side

				./mtglacier.pl restore --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log --max-number-of-files=10
    
9. Wait 4+ hours
10. Download restored files back to backup location

				./mtglacier.pl restore-completed --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log
    
11. Delete all your files from vault

				./mtglacier.pl purge-vault --config=glacier.cfg --from-dir /data/backup --to-vault=myvault -journal=journal.log

