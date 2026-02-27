# Amahi Home Server
# Copyright (C) 2007-2013 Amahi
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License v3
# (29 June 2007), as published in the COPYING file.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# file COPYING for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Amahi
# team at http://www.amahi.org/ under "Contact Us."


class SystemUtils
  def self.uptime
    self.run "uptime"
  end

  def self.run (cmd)
    pipe = IO.popen(cmd)
    ret = pipe.read
    pipe.close
    ret
  end

  def self.run_script(script, name, environment = {})
    require 'tempfile'
    require 'shellwords'
    include Process

    # number of linear backoff steps to wait. 22 ~= 160s
    steps = 25
    # duration of the base step for the sleep checks
    base_duration = 0.5
    f = Tempfile.new "run_script"
    File.chmod(0700, f.path)
    f.write(script)
    f.close
    ret = 0
    safe_name = Shellwords.escape(name)
    pid = fork
    unless pid
      # child
      environment.each_pair { |k,v| ENV[k] =v }
      if script[0..1] =~ /^#!/
        exec("#{f.path} #{safe_name} 2>&1")
      else
        exec("bash #{f.path} #{safe_name} 2>&1")
      end
    else
      # parent
      i = 1
      status = nil
      done = false
      until done
        sleep(base_duration * i)
        i+=1
        (x, status) = Process.waitpid2(pid, Process::WNOHANG)
        done = status.nil? ? (i > steps) : true
      end
      # if status is still nil, we have to kill the process
      unless status
        Process.kill("KILL", pid)
        raise "run_script had to KILL this script. it was taking too long. sorry."
      else
        ret = status.exitstatus
      end
    end
  end

  def self.unpack(url, fname)
    require 'shellwords'
    require 'shell'
    safe_fname = Shellwords.escape(fname)
    if (url =~ /\.zip$/)
      Shell.run("unzip -q #{safe_fname}")
    elsif (url =~ /\.(tar.gz|tgz)$/)
      Shell.run("tar -xzf #{safe_fname}")
    elsif (url =~ /\.(tar.bz2)$/)
      Shell.run("tar -xjf #{safe_fname}")
    else
      raise "File #{url} is not supported for unpacking — report to the Amahi-kai community!"
    end
  end

end
