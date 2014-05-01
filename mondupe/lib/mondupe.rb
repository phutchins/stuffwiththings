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
    sleep 30
    system("#{knife_exec} bootstrap #{instance_ipaddress} -N #{instance_fqdn[0...-1]} -E #{chef_environment} -i #{chef_identity_file} -r #{chef_run_list} -x #{ssh_user} --sudo")
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
    `ssh -i ~/.ssh/DevOps.pem #{ssh_user}@#{instance_ip} "cd #{dump_tmp_path} && wget '#{download_url}' -O #{File.join(dump_tmp_path, dump_file_name)} 2&>1"`
    puts "#{Time.now.to_s} - Download completed"
  end

  def restore_db(instance_ip, dump_tmp_path, ssh_key, ssh_user, dump_file_name)
    # Restore from the database dump
    # TODO - Fail the process if any step fails
    puts "#{Time.now.to_s} - Dropping existing database"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "echo 'db.dropDatabase()' | mongo cde_production"`
    if $?.success? then puts "#{Time.now.to_s} - Database drop complete" else die("Error dropping database") end
    puts "Restoring Mongo Database from extracted dump: #{File.join(dump_tmp_path, "cde_production")}"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "cd #{dump_tmp_path}; tar xf #{dump_file_name}; time mongorestore /tmp/cde_production"`
    puts "Removing database archive file"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "rm -rf #{File.join(dump_tmp_path, dump_file_name)}"`
    puts "#{Time.now.to_s} - Removing saved searches"
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "mongo cde_production --eval \\"db.users.update({save_searches: {$ne: null}}, {$unset: {save_searches: ''}}, {multi: true})\\""`
    puts "#{Time.now.to_s} - Cleaning up our mess..."
    `ssh -i #{ssh_key} #{ssh_user}@#{instance_ip} "rm -rf #{File.join(dump_tmp_path, 'cde_production')}"`
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
