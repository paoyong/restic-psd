using System.Collections.Generic;

namespace acorn.Models
{
    public class BackupSchedule
    {
        public int IntervalHours { get; set; } = 1;
        public string RepoFolder { get; set; } = "";
        public int SnapshotCount { get; set; } = 5;
    }

    public class AppConfig
    {
        public bool BackupsEnabled { get; set; } = true;
        public List<string> FoldersWatched { get; set; } = new();
        public List<string> IncludePatterns { get; set; } = new() { "*WORKING*" };
        public List<string> ExcludePatterns { get; set; } = new() { "*.tmp", "*.log", "Thumbs.db" };
        public List<BackupSchedule> Schedules { get; set; } = new();
    }
}
