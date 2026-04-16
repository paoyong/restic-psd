using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using acorn.Models;
using Windows.Storage;

namespace acorn.Services
{
    public static class TaskSchedulerService
    {
        private static readonly string ScriptsFolder =
            Path.Combine(ApplicationData.Current.LocalFolder.Path, "Scripts");

        private const string TaskFolderPrefix = "Acorn\\Backup_";
        private const int MaxTrackedTasks = 50;

        public static void Apply(AppConfig config)
        {
            Directory.CreateDirectory(ScriptsFolder);

            // Remove all previously registered tasks (brute-force up to MaxTrackedTasks)
            for (int i = 0; i < MaxTrackedTasks; i++)
                RemoveTask($"{TaskFolderPrefix}{i}");

            if (!config.BackupsEnabled) return;

            for (int i = 0; i < config.Schedules.Count; i++)
            {
                var schedule = config.Schedules[i];
                if (string.IsNullOrWhiteSpace(schedule.RepoFolder)) continue;

                var taskName   = $"{TaskFolderPrefix}{i}";
                var scriptPath = GenerateScript(config, schedule, i);
                var totalMin   = (int)Math.Round(schedule.IntervalHours * 60);

                if (totalMin >= 1440)
                    RegisterDailyTask(taskName, scriptPath, schedule.StartTime);
                else
                    RegisterMinuteTask(taskName, scriptPath, Math.Max(1, totalMin));
            }
        }

        // ── Script generation ─────────────────────────────────────────────────

        private static string GenerateScript(AppConfig config, BackupSchedule schedule, int index)
        {
            var path    = Path.Combine(ScriptsFolder, $"backup_{index}.ps1");
            var keyFile = Path.Combine(ScriptsFolder, "restic.key");

            string QuoteList(System.Collections.Generic.IEnumerable<string> items) =>
                string.Join(", ", items.Select(i => "'" + i.Replace("'", "''") + "'"));

            var folderArgs  = QuoteList(config.FoldersWatched);
            var includeArgs = QuoteList(config.IncludePatterns.Select(p => "--include=" + p));
            var excludeArgs = QuoteList(config.ExcludePatterns.Select(p => "--exclude=" + p));

            var sb = new System.Text.StringBuilder();
            sb.AppendLine("$ErrorActionPreference = 'Stop'");
            sb.AppendLine("$restic = 'restic'");
            sb.AppendLine($"$env:RESTIC_REPOSITORY = '{schedule.RepoFolder.Replace("'", "''")}'");
            sb.AppendLine($"$env:RESTIC_PASSWORD_FILE = '{keyFile.Replace("'", "''")}'");
            sb.AppendLine();
            sb.AppendLine($"$folders = @({folderArgs})");
            sb.AppendLine($"$bkArgs  = @({includeArgs}, {excludeArgs})");
            sb.AppendLine();
            sb.AppendLine("if (-not (Test-Path $env:RESTIC_REPOSITORY)) {");
            sb.AppendLine("    New-Item -ItemType Directory -Force -Path $env:RESTIC_REPOSITORY | Out-Null");
            sb.AppendLine("    & $restic init");
            sb.AppendLine("}");
            sb.AppendLine();
            sb.AppendLine("& $restic backup $folders $bkArgs --no-scan");
            sb.AppendLine($"& $restic forget --keep-last {schedule.SnapshotCount} --prune");

            File.WriteAllText(path, sb.ToString());
            return path;
        }

        // ── schtasks helpers ──────────────────────────────────────────────────

        private static void Schtasks(string args)
        {
            using var p = Process.Start(new ProcessStartInfo("schtasks.exe", args)
            {
                CreateNoWindow = true,
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            });
            p?.WaitForExit();
        }

        private static string PsCommand(string scriptPath) =>
            $"powershell.exe -ExecutionPolicy Bypass -NonInteractive -File \"{scriptPath}\"";

        private static void RegisterMinuteTask(string name, string scriptPath, int minutes)
        {
            RemoveTask(name);
            Schtasks($"/create /tn \"{name}\" /tr \"{PsCommand(scriptPath)}\" /sc minute /mo {minutes} /f");
        }

        private static void RegisterDailyTask(string name, string scriptPath, string time)
        {
            RemoveTask(name);
            Schtasks($"/create /tn \"{name}\" /tr \"{PsCommand(scriptPath)}\" /sc daily /st \"{time}\" /f");
        }

        public static void RemoveTask(string name) =>
            Schtasks($"/delete /tn \"{name}\" /f");
    }
}
