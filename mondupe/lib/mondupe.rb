#!/usr/bin/env ruby

require 'aws-sdk'

class Mondupe
  def create_instance(instance_name, instance_image_id, instance_type, instance_count, security_group, key_pair_name, expire_days, instance_owner, instance_volume_size)
    #AWS.config(:access_key_id => ENV['AWS_ACCESS_KEY_ID'], :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'], region: 'us-east-1')

    ec2 = AWS::EC2.new(:access_key_id => ENV['AWS_ACCESS_KEY_ID'], :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])
    key_pair = ec2.key_pairs[key_pair_name]

    # Use this to create a new security group - Can have preset options
    #security_group = ec2.security_groups.create("sg_#{instance_name}")
    #security_group = 'sg_my_awesome_new_instance'

    instance = ec2.instances.create(
      :image_id => instance_image_id,
      :block_device_mappings => [{
        :device_name => "/dev/sda1",
        :ebs => {
          :volume_size => instance_volume_size,
          :delete_on_termination => true
        }
      }],
      :instance_type => instance_type,
      :count => instance_count,
      :security_groups => [ security_group ],
      :key_pair => key_pair
    )

    created_date_time = Time.now.to_i

    # Display some information about the new instance
    puts "Instance '#{instance_name}' created with ID '#{instance.id}'"

    instance.tag('Name', :value => instance_name)
    instance.tag('owner', :value => instance_owner)
    instance.tag('expire_days', :value => expire_days)
    instance.tag('created', :value => created_date_time)
    instance.tag('mondupe')

    puts "Added tags... "
    puts "  Name: #{instance_name}"
    puts "  owner: #{instance_owner}"
    puts "  expires: #{expire_days}"
    puts "  created: #{created_date_time}"

    # Wait for instance to be ready
    current_state = ""
    until instance.status == :running
      if current_state != instance.status
        puts "Status: #{instance.status.to_s}"
        print "Instance coming up "
        current_state = instance.status
      else
        print "."
        sleep 1
      end
    end

    puts ""
    puts "Instance #{instance.id} is now running"
    puts "Name: #{instance.tags['Name']}"
    puts "IP: #{instance.ip_address}"
    puts "Public DNS: #{instance.dns_name}"
    instance
  end

  def create_dns(instance_fqdn, route53_domain, instance)
    # Set up DNS through Route53
    puts "Setting up Route53 DNS..."
    # Check to see if record exists
    route53 = AWS::Route53.new(:access_key_id => ENV['AWS_ACCESS_KEY_ID'], :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])
    zone = route53.hosted_zones.select { |z| z.name == route53_domain }.first

    rrsets = AWS::Route53::HostedZone.new(zone.id).rrsets
    rrset = rrsets.create(instance_fqdn, 'A', :ttl => 300, :resource_records => [{:value => instance.ip_address }])
    if rrset.exists?
      # Create new record if does not exist
      rrset.update
    else
      # Update if record exists
      rrset = zone.rrsets[instance_fqdn, 'A']
      rrset.resource_records = [ { :value => instance.ip_address } ]
      rrset.update
    end
  end


  def bootstrap(instance_name, instance_fqdn, instance_ipaddress, chef_environment, chef_identity_file, chef_run_list, ssh_user, knife_exec)
    # Bootstrap the new instance with chef
    puts "Bootstraping node with Chef..."
    puts "Running..."
    #puts "#{knife_exec} bootstrap #{instance_ipaddress} -N #{instance_fqdn[0...-1]} -E #{chef_environment} -i #{chef_identity_file} -r #{chef_run_list} -x #{ssh_user} --sudo"
    tries = 20
    begin
      sleep 30
      system("#{knife_exec} bootstrap #{instance_ipaddress} -N #{instance_fqdn[0...-1]} -E #{chef_environment} -i #{chef_identity_file} -r #{chef_run_list} -x #{ssh_user} --sudo") or raise "Knife bootstrap failed"
    rescue
      tries -= 1
      puts "Cannot connect to node, trying again... #{tries} left."
      retry if tries > 0
    end
  end

  def get_db_dump_from_s3(instance_ip, s3_bucket_name, dump_tmp_path, ssh_user, dump_file_name)
    expiration = Time.now.to_i + 400*60
    s3 = AWS::S3.new(:access_key_id => ENV['AWS_ACCESS_KEY_ID'], :secret_access_key => ENV['AWS_SECRET_ACCESS_KEY'])
    backups = s3.buckets[s3_bucket_name]
    latest_backup = backups.objects.sort_by {|backup| backup.last_modified}.last
    download_url = latest_backup.url_for(:get, :expires_in => expiration, :response_content_type => "application/json")
    puts "Download URL: #{download_url}"
    puts "#{Time.now.to_s} - Starting download."
    puts "  Please wait..."
    `ssh -i ~/.ssh/DevOps.pem #{ssh_user}@#{instance_ip} "sudo mkdir -p #{dump_tmp_path} && cd #{dump_tmp_path} && wget '#{download_url}' -O #{File.join(dump_tmp_path, dump_file_name)} 2&>1"`
    puts "#{Time.now.to_s} - Download completed"
  end

  def add_user(instance_ip, username, password, database, roles)
    #add db users here
  end

  def restore_db(instance_ip, dump_tmp_path, ssh_key, ssh_user, dump_file_name, mongo_db_name, mongo_user, mongo_pass, mongo_auth_db)
    # Restore from the database dump
    # TODO - Fail the process if any step fails
    abort "You must specify a database name to drop and restore. Use -n [name] or ENV['MONGO_DB_NAME'] to set this value." if mongo_db_name.nil?
    db_connect_string = "mongo #{mongo_db_name}"
    db_connect_string << " -u \"#{mongo_user}\" -p \"#{mongo_pass}\"" if !mongo_user.nil? && !mongo_pass.nil?
    db_connect_string << " --authenticationDatabase \"#{mongo_auth_db}\"" if !mongo_auth_db.nil?
    puts "#{Time.now.to_s} - Dropping existing database"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "echo 'db.dropDatabase()' | #{db_connect_string}"`
    if $?.success? then puts "#{Time.now.to_s} - Database drop complete" else abort("Error dropping database") end
    puts "Extracting database dump archive file..."
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "cd #{dump_tmp_path}; tar xf #{dump_file_name}"`
    if $?.success? then puts "#{Time.now.to_s} - Extraction complete!" else abort("Error extracting archive") end
    puts "Restoring Mongo Database from extracted dump: #{File.join(dump_tmp_path, "#{mongo_db_name}")}"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "time mongorestore #{File.join(dump_tmp_path, "#{mongo_db_name}")}"`
    if $?.success? then puts "#{Time.now.to_s} - Database restore complete!" else abort("Error restoring databse") end
    puts "Removing database archive file"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "rm -rf #{File.join(dump_tmp_path, dump_file_name)}"`
    if $?.success? then puts "#{Time.now.to_s} - Archive removed!" else abort("Error removing archive") end
    puts "#{Time.now.to_s} - Cleaning up our mess..."
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "rm -rf #{File.join(dump_tmp_path, "#{mongo_db_name}")}"`
    if $?.success? then puts "#{Time.now.to_s} - Mess cleaned up!" else abort("Error cleaning up after myself...") end
  end

  def execute_js(instance_dns, ssh_key, ssh_user, java_command, mongo_db_name, mongo_user, mongo_pass, mongo_auth_db)
    abort "You must specify a database name to execute java script against. Use -n [name] or ENV['MONGO_DB_NAME'] to set this value." if mongo_db_name.nil?
    db_connect_string = "mongo #{mongo_db_name}"
    db_connect_string << " -u \"#{mongo_user}\" -p \"#{mongo_pass}\"" if !mongo_user.nil? && !mongo_pass.nil?
    db_connect_string << " --authenticationDatabase \"#{mongo_auth_db}\"" if !mongo_auth_db.nil?
    puts "Connect String: #{db_connect_string}"
    puts "#{Time.now.to_s} - Running command on #{instance_dns} against #{mongo_db_name}"
    db_output = `ssh -i #{ssh_key} #{ssh_user}@#{instance_dns} "echo '#{java_command}' | #{db_connect_string}"`
    puts db_output
    if $?.success? then puts "#{Time.now.to_s} - Command execution complete" else abort("Error executing command") end
  end

  def terminate(instance_id)
    puts "function not quite ready yet"
  end

  def list
    puts "function not quite ready yet"
  end

  def expire(instance_id, instance_name, expire_days)
    puts "function not quite ready yet"
  end
end
