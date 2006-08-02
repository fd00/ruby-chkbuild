require 'fileutils'
require 'socket'
require "etc"
require "digest/sha2"
require "fcntl"
require "tempfile"

require 'chkbuild/cvs'

def tp(obj)
  open("/dev/tty", "w") {|f| f.puts obj.inspect }
end

module Kernel
  if !nil.respond_to?(:funcall)
    if nil.respond_to?(:fcall) 
      alias funcall fcall
    else
      alias funcall send
    end
  end
end

class IO
  def close_on_exec
    self.fcntl(Fcntl::F_GETFD) & Fcntl::FD_CLOEXEC != 0
  end

  def close_on_exec=(v)
    flags = self.fcntl(Fcntl::F_GETFD)
    if v
      flags |= Fcntl::FD_CLOEXEC
    else
      flags &= ~Fcntl::FD_CLOEXEC
    end
    self.fcntl(Fcntl::F_SETFD, flags)
    v
  end
end

class Build
  def Build.permutation(*args)
    if block_given?
      Build.permutation_each(*args) {|vs| yield vs }
    else
      r = []
      Build.permutation_each(*args) {|vs| r << vs }
      r
    end
  end

  def Build.permutation_each(*args)
    if args.empty?
      yield []
    else
      arg, *rest = args
      arg.each {|v|
        Build.permutation_each(*rest) {|vs|
          yield [v, *vs]
        }
      }
    end
  end

  def Build.mkcd(*args, &b) $Build.mkcd(*args, &b) end
  def mkcd(dir)
    FileUtils.mkpath dir
    Dir.chdir dir
  end

  def resource_unlimit(resource)
    if Symbol === resource
      begin
        resource = Process.const_get(resource)
      rescue NameError
        return
      end
    end
    cur_limit, max_limit = Process.getrlimit(resource)
    Process.setrlimit(resource, max_limit, max_limit)
  end

  def resource_limit(resource, val)
    if Symbol === resource
      begin
        resource = Process.const_get(resource)
      rescue NameError
        return
      end
    end
    cur_limit, max_limit = Process.getrlimit(resource)
    if max_limit < val
      val = max_limit
    end
    Process.setrlimit(resource, val, val)
  end

  def identical_file?(f1, f2)
    s1 = File.stat(f1)
    s2 = File.stat(f2)
    s1.dev == s2.dev && s1.ino == s2.ino
  end

  def sha256_digest_file(filename)
    d = Digest::SHA256.new
    open(filename) {|f|
      buf = ""
      while f.read(4096, buf)
        d << buf
      end
    }
    "sha256:#{d.hexdigest}"
  end

  def Build.svn(*args, &b) $Build.svn(*args, &b) end
  def svn(url, working_dir, opts={})
    opts = opts.dup
    opts[:section] ||= 'svn'
    if File.exist?(working_dir) && File.exist?("#{working_dir}/.svn")
      Dir.chdir(working_dir) {
        $Build.run "svn", "cleanup", opts
        opts[:section] = nil
        $Build.run "svn", "update", opts
      }
    else
      if File.exist?(working_dir)
        FileUtils.rm_rf(working_dir)
      end
      $Build.run "svn", "checkout", url, working_dir, opts
    end
  end

  def with_tempfile(content) # :yield: tempfile
    t = Tempfile.new("chkbuild")
    t << content
    t.sync
    yield t
  end

  def Build.gnu_savannah_cvs(*args, &b) $Build.gnu_savannah_cvs(*args, &b) end
  def gnu_savannah_cvs(proj, mod, branch, opts={})
    opts = opts.dup
    opts[:viewcvs] ||= "http://savannah.gnu.org/cgi-bin/viewcvs/#{proj}?diff_format=u"
    $Build.cvs(":pserver:anonymous@cvs.savannah.gnu.org:/sources/#{proj}", mod, branch, opts)
  end

  def Build.make(*args, &b) $Build.make(*args, &b) end
  def make(*targets)
    opts = {}
    opts = targets.pop if Hash === targets.last
    opts = opts.dup
    opts[:alt_commands] = ['make']
    if targets.empty?
      opts[:section] ||= 'make'
      $Build.run("gmake", opts)
    else
      targets.each {|target|
	h = opts.dup
	h[:reason] = target
        h[:section] = target
        $Build.run("gmake", target, h)
      }
    end
  end

  def self.rsync_ssh_upload_target(rsync_target, private_key=nil)
    Build.add_upload_hook {|name|
      Build.do_upload_rsync_ssh(rsync_target, private_key, name)
    }
  end

  def self.do_upload_rsync_ssh(rsync_target, private_key, name)
    if %r{\A(?:([^@:]+)@)([^:]+)::(.*)\z} !~ rsync_target
      raise "invalid rsync target: #{rsync_target.inspect}"
    end
    remote_user = $1 || ENV['USER'] || Etc.getpwuid.name
    remote_host = $2
    remote_path = $3
    local_host = Socket.gethostname
    private_key ||= "#{ENV['HOME']}/.ssh/chkbuild-#{local_host}-#{remote_host}"

    pid = fork {
      ENV.delete 'SSH_AUTH_SOCK'
      exec "rsync", "--delete", "-rte", "ssh -akxi #{private_key}", "#{Build.public_dir}/#{name}", "#{rsync_target}"
    }
    Process.wait pid
  end
end