review_protocol
===============

tool to generate review protocol with svn logs


##Usage

Usage: review_protocol.rb [options]

    -d, --directory DIRECTORY        svn directory of source code
    -r, --reviewers 1,2,3...         list of reviewer names
    -p, --project PROJECT            project name, used in file name (e.g Pj117)
    -k, --package PACKAGE            generate protocol (only) for this (work)package
        --rev FROM:TO                valid revision range
    		--pdf                        convert report to pdf as well