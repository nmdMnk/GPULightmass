#include <Windows.h>
#include <cstdio>
#include <string>
#include <random>
#include <ctime>

static std::string ReportFileName;

const int REPORT_INTERVAL = 100;

void ReportProgress(std::string CurrentText, int CurrentValue, std::string OverallText, int OverallValue, bool IgnoreReportInterval)
{
	static clock_t lastReportTime = clock();
	if (clock() - lastReportTime > REPORT_INTERVAL || IgnoreReportInterval)
	{
		lastReportTime = clock();
		FILE* fp = nullptr;
		fopen_s(&fp, ReportFileName.c_str(), "w");
		if (fp)
		{
			fprintf(fp, "%s\n%d\n%s\n%d\n", CurrentText.c_str(), CurrentValue, OverallText.c_str(), OverallValue);
			fclose(fp);
		}
	}
}

void StartProgressReporter()
{
	std::random_device rd;
	std::mt19937 engine{ rd() };
	ReportFileName = "GPULIGHTMASS_PROGRESSREPORT_" + std::to_string(engine()) + ".log";
	ReportProgress("Starting", 0, "", 0, true);
	ShellExecute(0, NULL, "ProgressReporter.exe", ReportFileName.c_str(), NULL, SW_SHOWNORMAL);
}

size_t FinishedTexels = 0;
size_t TotalTexels = 1;

void SetTotalTexels(size_t InTotalTexels)
{
	TotalTexels = InTotalTexels;
}

void ReportCurrentFinishedTexels(size_t CurrentFinishedTexels)
{
	FinishedTexels += CurrentFinishedTexels;
}

void ReportProgressTextureMapping(
	int CurrentBlock,
	int TotalBlock,
	float elapsedTime,
	double LastRayTracingPerformance,
	double accumulatedGPUTime,
	double OverallRayTracingPerformance
)
{
	CurrentBlock++;

	int etaInSeconds = FinishedTexels > 0 ? static_cast<int>(accumulatedGPUTime / 1000.0 / FinishedTexels * (TotalTexels - FinishedTexels)) : 0;
	int etaSecond = max(etaInSeconds % 60, 0);
	int etaMinute = max((etaInSeconds / 60) % 60, 0);
	int etaHour = max(etaInSeconds / 60 / 60, 0);

	char progressTextBuffer[256];
	char overallTextBuffer[256];
	sprintf_s(progressTextBuffer, "Current batch %.2lf%%  Block %d/%d", CurrentBlock * 100.0 / TotalBlock, CurrentBlock, TotalBlock);
	sprintf_s(overallTextBuffer, "Overall texel progress %.2lf%% %zu/%zu  [Perf: last %.2fs %.2fMrays/s overall %.2fs %.2fMrays/s] [ETA: %02d:%02d:%02d]", 
		FinishedTexels * 100.0 / TotalTexels,
		FinishedTexels,
		TotalTexels, 
		elapsedTime / 1000.0,
		LastRayTracingPerformance, 
		accumulatedGPUTime / 1000.0, 
		OverallRayTracingPerformance,
		etaHour,
		etaMinute,
		etaSecond);

	ReportProgress(
		progressTextBuffer,
		(int)(CurrentBlock * 100.0 / TotalBlock),
		overallTextBuffer,
		(int)(FinishedTexels * 100.0 / TotalTexels),
		false
	);
}
