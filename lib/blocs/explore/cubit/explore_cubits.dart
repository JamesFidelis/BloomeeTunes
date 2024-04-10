// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:developer';
import 'dart:isolate';
import 'package:Bloomee/services/db/GlobalDB.dart';
import 'package:bloc/bloc.dart';
import 'package:Bloomee/model/MediaPlaylistModel.dart';
import 'package:Bloomee/model/chart_model.dart';
import 'package:Bloomee/plugins/chart_defines.dart';
import 'package:Bloomee/repository/Youtube/yt_charts_home.dart';
import 'package:Bloomee/screens/screen/chart/show_charts.dart';
import 'package:Bloomee/services/db/bloomee_db_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

part 'explore_states.dart';

class TrendingCubit extends Cubit<TrendingCubitState> {
  bool isLatest = false;
  TrendingCubit() : super(TrendingCubitInitial()) {
    getTrendingVideosFromDB();
    getTrendingVideos();
  }

  void getTrendingVideos() async {
    List<ChartModel> ytCharts = await fetchTrendingVideos();
    ChartModel chart = ytCharts[0]
      ..chartItems = getFirstElements(ytCharts[0].chartItems!, 16);
    emit(state.copyWith(ytCharts: [chart]));
    isLatest = true;
  }

  List<ChartItemModel> getFirstElements(List<ChartItemModel> list, int count) {
    return list.length > count ? list.sublist(0, count) : list;
  }

  void getTrendingVideosFromDB() async {
    ChartModel? ytChart = await BloomeeDBService.getChart("Trending Videos");
    if ((!isLatest) &&
        ytChart != null &&
        (ytChart.chartItems?.isNotEmpty ?? false)) {
      ChartModel chart = ytChart
        ..chartItems = getFirstElements(ytChart.chartItems!, 16);
      emit(state.copyWith(ytCharts: [chart]));
    }
  }
}

class RecentlyCubit extends Cubit<RecentlyCubitState> {
  StreamSubscription<void>? watcher;
  RecentlyCubit() : super(RecentlyCubitInitial()) {
    getRecentlyPlayed();
    watchRecentlyPlayed();
  }

  Future<void> watchRecentlyPlayed() async {
    (await BloomeeDBService.watchRecentlyPlayed()).listen((event) {
      getRecentlyPlayed();
      log("Recently Played Updated");
    });
  }

  @override
  Future<void> close() {
    watcher?.cancel();
    return super.close();
  }

  void getRecentlyPlayed() async {
    final mediaPlaylist = await BloomeeDBService.getRecentlyPlayed(limit: 15);
    emit(state.copyWith(mediaPlaylist: mediaPlaylist));
  }
}

class ChartCubit extends Cubit<ChartState> {
  ChartInfo chartInfo;
  StreamSubscription? strm;
  FetchChartCubit fetchChartCubit;
  ChartCubit(
    this.chartInfo,
    this.fetchChartCubit,
  ) : super(ChartInitial()) {
    getChartFromDB();
    initListener();
  }
  void initListener() {
    strm = fetchChartCubit.stream.listen((state) {
      if (state.isFetched) {
        log("Chart Fetched from Isolate - ${chartInfo.title}",
            name: "Isolate Fetched");
        getChartFromDB();
      }
    });
  }

  Future<void> getChartFromDB() async {
    final chart = await BloomeeDBService.getChart(chartInfo.title);
    if (chart != null) {
      emit(state.copyWith(
          chart: chart, coverImg: chart.chartItems?.first.imageUrl));
    }
  }

  @override
  Future<void> close() {
    fetchChartCubit.close();
    strm?.cancel();
    return super.close();
  }
}

class FetchChartCubit extends Cubit<FetchChartState> {
  FetchChartCubit() : super(FetchChartInitial()) {
    fetchCharts();
  }

  Future<void> fetchCharts() async {
    String _path = (await getApplicationDocumentsDirectory()).path;
    BackgroundIsolateBinaryMessenger.ensureInitialized(
        ServicesBinding.rootIsolateToken!);

    final chartList = await Isolate.run<List<ChartModel>>(() async {
      log(_path, name: "Isolate Path");
      List<ChartModel> _chartList = List.empty(growable: true);
      ChartModel chart;
      final db = await Isar.open(
        [
          ChartsCacheDBSchema,
        ],
        directory: _path,
      );
      for (var i in chartInfoList) {
        final chartCacheDB = db.chartsCacheDBs
            .where()
            .filter()
            .chartNameEqualTo(i.title)
            .findFirstSync();
        bool _shouldFetch = (chartCacheDB?.lastUpdated
                    .difference(DateTime.now())
                    .inHours
                    .abs() ??
                80) >
            16;
        log("Last Updated - ${(chartCacheDB?.lastUpdated.difference(DateTime.now()).inHours)?.abs()} Hours before ",
            name: "Isolate");

        if (_shouldFetch) {
          chart = await i.chartFunction(i.url);
          if ((chart.chartItems?.isNotEmpty) ?? false) {
            db.writeTxnSync(() =>
                db.chartsCacheDBs.putSync(chartModelToChartCacheDB(chart)));
          }
          log("Chart Fetched - ${chart.chartName}", name: "Isolate");
          _chartList.add(chart);
        }
      }
      db.close();
      return _chartList;
    });

    if (chartList.isNotEmpty) {
      emit(state.copyWith(isFetched: true));
    }
  }
}
