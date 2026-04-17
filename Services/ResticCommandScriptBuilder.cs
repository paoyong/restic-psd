using System;
using System.Collections.Generic;
using System.CommandLine;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using acorn.Models;

namespace acorn.Services
{
    internal static class ResticCommandScriptBuilder
    {
        public static string BuildConfigKey(string configPath)
        {
            var fileName = Path.GetFileNameWithoutExtension(configPath);
            var slug = Regex.Replace(fileName.ToLowerInvariant(), "[^a-z0-9]+", "_").Trim('_');

            if (string.IsNullOrWhiteSpace(slug))
                slug = "config";

            using var sha = SHA256.Create();
            var hash = Convert.ToHexString(sha.ComputeHash(Encoding.UTF8.GetBytes(configPath))).ToLowerInvariant();
            return $"{slug}_{hash[..8]}";
        }

        public static string BuildBatchScript(AppConfig config, BackupSchedule schedule, string keyFilePath)
        {
            var lines = new List<string>
            {
                "@echo off",
                "setlocal",
                $"set \"RESTIC_REPOSITORY={schedule.RepoFolder}\"",
                $"set \"RESTIC_PASSWORD_FILE={keyFilePath}\"",
                string.Empty,
                "if not exist \"%RESTIC_REPOSITORY%\" (",
                "    mkdir \"%RESTIC_REPOSITORY%\"",
                "    if errorlevel 1 exit /b %errorlevel%",
                $"    {BuildInitCommandLine()}",
                "    if errorlevel 1 exit /b %errorlevel%",
                ")",
                string.Empty,
                BuildBackupCommandLine(config),
                "if errorlevel 1 exit /b %errorlevel%",
                BuildForgetCommandLine(schedule),
                "exit /b %errorlevel%"
            };

            return string.Join(Environment.NewLine, lines) + Environment.NewLine;
        }

        private static string BuildInitCommandLine() =>
            RenderAndValidate(new[] { "init" }, CreateRootCommand());

        private static string BuildBackupCommandLine(AppConfig config)
        {
            var tokens = new List<string> { "backup" };
            tokens.AddRange(config.FoldersWatched);

            foreach (var pattern in config.IncludePatterns)
            {
                tokens.Add("--include");
                tokens.Add(pattern);
            }

            foreach (var pattern in config.ExcludePatterns)
            {
                tokens.Add("--exclude");
                tokens.Add(pattern);
            }

            tokens.Add("--no-scan");
            return RenderAndValidate(tokens, CreateRootCommand());
        }

        private static string BuildForgetCommandLine(BackupSchedule schedule)
        {
            var tokens = new[]
            {
                "forget",
                "--keep-last",
                schedule.SnapshotCount.ToString(),
                "--prune"
            };

            return RenderAndValidate(tokens, CreateRootCommand());
        }

        private static RootCommand CreateRootCommand()
        {
            var root = new RootCommand("restic");

            var init = new Command("init");
            root.Subcommands.Add(init);

            var backup = new Command("backup");
            var pathArgument = new Argument<string[]>("paths")
            {
                Arity = ArgumentArity.OneOrMore
            };
            var includeOption = new Option<string[]>("--include")
            {
                Arity = ArgumentArity.ZeroOrMore,
                AllowMultipleArgumentsPerToken = true
            };
            var excludeOption = new Option<string[]>("--exclude")
            {
                Arity = ArgumentArity.ZeroOrMore,
                AllowMultipleArgumentsPerToken = true
            };
            var noScanOption = new Option<bool>("--no-scan");

            backup.Arguments.Add(pathArgument);
            backup.Options.Add(includeOption);
            backup.Options.Add(excludeOption);
            backup.Options.Add(noScanOption);
            root.Subcommands.Add(backup);

            var forget = new Command("forget");
            var keepLastOption = new Option<int>("--keep-last");
            var pruneOption = new Option<bool>("--prune");

            forget.Options.Add(keepLastOption);
            forget.Options.Add(pruneOption);
            root.Subcommands.Add(forget);

            return root;
        }

        private static string RenderAndValidate(IReadOnlyList<string> tokens, RootCommand root)
        {
            var parseResult = root.Parse(tokens);
            if (parseResult.Errors.Count > 0)
                throw new InvalidOperationException("Invalid restic command definition: " + string.Join("; ", parseResult.Errors.Select(error => error.Message)));

            return "restic " + string.Join(" ", tokens.Select(QuoteBatchToken));
        }

        private static string QuoteBatchToken(string token)
        {
            if (string.IsNullOrEmpty(token))
                return "\"\"";

            var needsQuotes = token.Any(char.IsWhiteSpace) || token.Contains('"');
            if (!needsQuotes)
                return token;

            return "\"" + token.Replace("\"", "\"\"") + "\"";
        }
    }
}
