#!/usr/bin/env ruby

require 'rubygems'
require 'bundler/setup'
require 'aws-sdk'
require 'uuid'

opsworks = AWS:OpsWorks.new
