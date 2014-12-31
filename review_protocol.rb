#!/usr/bin/env ruby

require 'ostruct'
require "erb"
require "rexml/document"
require 'optparse'

REPORT_TEMPLATE = <<-HERE
-----------------------------------------------------------------------
REVIEW RECORD

Id:               <%= @project %>-CIR-<%=Time.now.strftime("%Y%m%d_%H%M%S")%>-<%=@reviewer%>
Printout time:    <%= Time.now %>
Reviewer:         <%= @reviewer %>

Path used:        <%= Report.svnPath %>
----------------------------------------------------------------------

Reviewed revisions:

<% @commits.each do |commit| %>
<%= commit[:revision] %>	<%= commit[:author] %>	<%= commit[:date] %>	<%= commit[:reviewer] -%>
		<% commit[:paths].each do |changedFile| %>
			<%= changedFile.strip -%>
		<% end %>
		Number of changed files: <%= commit[:paths].length %>
		<%= commit[:msg].gsub('\n', ' ') %>
<% end %>

Reviewer signature: ______________________________
                    (<%= @reviewer %>)
HERE

module SvnLog

	module ClassMethods
		attr_reader :svnPath, :svnLogs

		def svnLog(svnPath, validRevisions)
			@svnPath = svnPath
			logCmd = "svn log -v --xml #{@svnPath}"
			logCmd += " -r #{validRevisions}" if validRevisions
			puts logCmd
			`#{logCmd}`
		end

		def parseLog(svnPath, validRevisions)
			xmlLog = svnLog(svnPath, validRevisions)
			doc = REXML::Document.new(xmlLog)
			@svnLogs = []
			doc.elements.each('log/logentry') do |logentry|
				commit = {}
   			commit[:revision] = logentry.attributes["revision"]
   			commit[:author] = logentry.elements["author"].text
   			commit[:date] = logentry.elements["date"].text
   			commit[:paths] = []
   			logentry.elements["paths"].elements.each do |path|
   			 	commit[:paths] << "#{path.attributes["action"]}  #{path.text}"
   			end
   			commit[:msg] = logentry.elements["msg"].text
   			commit[:reviewer] = firstMatch commit[:msg], /<(.*?)>/
   			commit[:project] = firstMatch commit[:msg], /\[pj(.*?)\]/i
   			commit[:package] =  firstMatch commit[:msg], /\[wp(.*?)\]/i
   			@svnLogs << commit
			end
		end

		def firstMatch(msg, regx)
			msg && match = msg.match(regx)
			match.to_s[1...-1] if match
		end
	end
	
	def self.included(receiver)
		receiver.extend ClassMethods
	end
end

module Renderable
	attr_accessor :fileName
	
	def save
    File.open(@fileName, "w+") do |f|
      f.write(render)
    end
    @fileName
  end

	def render
		ERB.new(REPORT_TEMPLATE, nil, '-').result binding
	end
end


class Report
	include SvnLog
	include Renderable

	attr_reader :reviewer, :project, :package, :commits

	def initialize(reviewer, project, package)
			@commits = []
			@reviewer = reviewer
			@project = project
			@package = package
	end

	def generate
		@commits = Report.svnLogs.clone
		@commits.keep_if do |commit|
			expectedCommit? commit
		end
	end

	def expectedCommit?(commit) 
		reviewerFit = (commit[:reviewer].nil? && @reviewer.nil?) ||
									(commit[:reviewer] && @reviewer && 
										@reviewer.casecmp(commit[:reviewer]).zero?)
		projectFit = @project.nil? || (@project && commit[:project] && 
																	 @project.casecmp(commit[:project]).zero?)
		packageFit = @package.nil? || (@package && commit[:package] && 
																	 @package.casecmp(commit[:package]).zero?)
		reviewerFit && projectFit && packageFit
	end

end

def generateReport(reviewer, project, package)
	report = Report.new(reviewer, project, package)
	report.fileName ="#{project}-CIR-#{Time.now.strftime("%Y%m%d_%H%M%S")}-#{reviewer}.txt"
	report.generate
	puts "Generated Report #{report.fileName}"
	report.save
end

def convertToPdf(file)
	require "prawn"
	pdf = Prawn::Document.new
	pdf.text File.read(file)
	pdf.render_file "#{File.basename(file, '.txt')}.pdf"
end

options = OpenStruct.new
optparse = OptionParser.new do |opts|
  opts.banner = "Usage: review_protocol.rb [options]"

  opts.on("", "--rev FROM:TO", String, "valid revision range") do |v|
    options.revision = v
  end

  opts.on("-d", "--directory DIRECTORY", "svn directory of source code") do |v| 
  	options.directory = v
  end
  opts.on("-r", "--reviewers 1,2,3...", Array, "list of reviewer names") do |list| 
  	options.reviewers = list
  end

 	opts.on("-p", "--project PROJECT", "project name, used in file name (e.g Pj117)") do |v|
 		options.project = v
 	end

 	opts.on("-k", "--package PACKAGE", "generate protocol (only) for this (work)package") do |v| 
 		options.package = v
 	end

 	opts.on("-k", "--pdf", "convert report to pdf as well") do |v| 
 		options.send("pdf?=", v)
 	end

end

begin
  optparse.parse!
  p options
  mandatory = [:directory, :reviewers]              
  missing = mandatory.select{ |param| options[param].nil? }        
  if not missing.empty?                                            
    puts "Missing options: #{missing.join(', ')}"                  
    puts optparse                                                  
    exit                                                           
  end                                                              
rescue OptionParser::InvalidOption, OptionParser::MissingArgument      
  puts $!.to_s                                                           
  puts optparse                                                          
  exit                                                                   
end    

Report.parseLog(options.directory, options.revision)
options.reviewers.each do |reviewer|
	file = generateReport reviewer, options.project, options.package
	convertToPdf file if options.pdf?
end

