Recently I decided to back up family photos onto iCloud (via iCloud for Windows) as well as onto a portable hard drive. 
Due to the volume of photos and various quirks of how family photos had been saved I implemented a few Powershell scripts to help with things like renaming files to avoid namespace collisions and restoring the date created of copied files. 
My experience in Powershell is limited but this was a good opportunity to get more familiar with it. 

Most of the functions in the module are unlikely to be perfect solutions to other scenarios out of the box, but for anyone struggling with similar problems (and based on Stack Overflow that's a non-zero amount of people) they should be easily adaptable. 

Please note that the Set-CreationDate function relies on [ExifDateTime.psm1](https://github.com/chestercodes/ExifDateTime) having been imported. chestercodes' fork of the respository is needed for their reimplementation of Update-ExifDateTaken. I'll look into adding a module manifest soon. 
