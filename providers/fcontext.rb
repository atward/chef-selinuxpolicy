include Chef::SELinuxPolicy::Helpers

# Support whyrun
def whyrun_supported?
  true
end

def fcontext_defined(file_spec, file_type, label = nil)
  file_hash = {
    'a' => 'all files',
    'f' => 'regular file',
    'd' => 'directory',
    'c' => 'character device',
    'b' => 'block device',
    's' => 'socket',
    'l' => 'symbolic link',
    'p' => 'named pipe'
  }

  label_matcher = label ? "system_u:object_r:#{Regexp.escape(label)}:s0\\s*$" : ''
  "semanage fcontext -l | grep -qP '^#{Regexp.escape(file_spec)}\\s+#{Regexp.escape(file_hash[file_type])}\\s+#{label_matcher}'"
end

def restorecon(file_spec)
  path = file_spec.to_s.sub(/\\/, '') # Remove backslashes
  return "restorecon -i #{path}" if ::File.exist?(path) # Return if it's not a regular expression
  path.count('/').times do
    path = ::File.dirname(path) # Splits at last '/' and returns front part
    break if ::File.directory?(path)
  end
  # This will restore the selinux file context recursively.
  "restorecon -iR #{path}"
end

def semanage_options(file_type)
  # Set options for file_type
  if node[:platform_family].include?('rhel') && Chef::VersionConstraint.new('< 7.0').include?(node['platform_version'])
    file_type_option = case file_type
                       when 'a' then '-f ""'
                       when 'f' then '-f --'
                       else; "-f -#{file_type}"
    end
  else
    file_type_option = "-f #{file_type}"
  end

  options = file_type_option

  options
end

use_inline_resources

# Run restorecon to fix label
def selinux_fcontext_relabel_resources(relabel_action=:nothing)
  execute "selinux-fcontext-#{new_resource.secontext}-relabel" do
    command lazy { restorecon(new_resource.file_spec) }
    action relabel_action
  end
end

action :relabel do
  selinux_fcontext_relabel_resources(:run)
end

# Create if doesn't exist, do not touch if fcontext is already registered
action :add do
  selinux_fcontext_relabel_resources
  escaped_file_spec = Regexp.escape(new_resource.file_spec)
  execute "selinux-fcontext-#{new_resource.secontext}-add" do
    command "/usr/sbin/semanage fcontext -a #{semanage_options(new_resource.file_type)} -t #{new_resource.secontext} '#{new_resource.file_spec}'"
    not_if fcontext_defined(new_resource.file_spec, new_resource.file_type)
    only_if { use_selinux }
    notifies :run, "execute[selinux-fcontext-#{new_resource.secontext}-relabel]", :immediate
  end
end

# Delete if exists
action :delete do
  selinux_fcontext_relabel_resources
  escaped_file_spec = Regexp.escape(new_resource.file_spec)
  execute "selinux-fcontext-#{new_resource.secontext}-delete" do
    command "/usr/sbin/semanage fcontext #{semanage_options(new_resource.file_type)} -d '#{new_resource.file_spec}'"
    only_if fcontext_defined(new_resource.file_spec, new_resource.file_type, new_resource.secontext)
    only_if { use_selinux }
    notifies :run, "execute[selinux-fcontext-#{new_resource.secontext}-relabel]", :immediate
  end
end

action :modify do
  selinux_fcontext_relabel_resources
  execute "selinux-fcontext-#{new_resource.secontext}-modify" do
    command "/usr/sbin/semanage fcontext -m #{semanage_options(new_resource.file_type)} -t #{new_resource.secontext} '#{new_resource.file_spec}'"
    only_if { use_selinux }
    only_if fcontext_defined(new_resource.file_spec, new_resource.file_type)
    not_if  fcontext_defined(new_resource.file_spec, new_resource.file_type, new_resource.secontext)
    notifies :run, "execute[selinux-fcontext-#{new_resource.secontext}-relabel]", :immediate
  end
end

action :addormodify do
  run_action(:add)
  run_action(:modify)
end
