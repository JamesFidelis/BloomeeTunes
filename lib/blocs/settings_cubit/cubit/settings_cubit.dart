import 'dart:developer';
import 'package:Bloomee/routes_and_consts/global_str_consts.dart';
import 'package:Bloomee/services/db/bloomee_db_service.dart';
import 'package:bloc/bloc.dart';
import 'package:path_provider/path_provider.dart';
part 'settings_state.dart';

class SettingsCubit extends Cubit<SettingsState> {
  SettingsCubit() : super(SettingsInitial()) {
    initSettings();
    autoUpdate();
  }

  void initSettings() {
    BloomeeDBService.getSettingBool(GlobalStrConsts.autoUpdateNotify)
        .then((value) {
      emit(state.copyWith(autoUpdateNotify: value ?? false));
    });

    BloomeeDBService.getSettingBool(GlobalStrConsts.autoSlideCharts)
        .then((value) {
      emit(state.copyWith(autoSlideCharts: value ?? true));
    });

    // Directory dir = Directory('/storage/emulated/0/Music');
    String? path;

    BloomeeDBService.getSettingStr(GlobalStrConsts.downPathSetting)
        .then((value) async {
      await getDownloadsDirectory().then((value) {
        if (value != null) {
          path = value.path;
        }
      });
      emit(state.copyWith(
          downPath: (value ?? path) ??
              (await getApplicationDocumentsDirectory()).path));
    });

    BloomeeDBService.getSettingStr(GlobalStrConsts.downQuality,
            defaultValue: '320 kbps')
        .then((value) {
      emit(state.copyWith(downQuality: value ?? "320 kbps"));
    });

    BloomeeDBService.getSettingStr(GlobalStrConsts.ytDownQuality).then((value) {
      emit(state.copyWith(ytDownQuality: value ?? "High"));
    });

    BloomeeDBService.getSettingStr(
      GlobalStrConsts.strmQuality,
    ).then((value) {
      emit(state.copyWith(strmQuality: value ?? "96 kbps"));
    });

    BloomeeDBService.getSettingStr(GlobalStrConsts.ytStrmQuality).then((value) {
      if (value == "High" || value == "Low") {
        emit(state.copyWith(ytStrmQuality: value ?? "Low"));
      } else {
        BloomeeDBService.putSettingStr(GlobalStrConsts.ytStrmQuality, "Low");
        emit(state.copyWith(ytStrmQuality: "Low"));
      }
    });

    BloomeeDBService.getSettingStr(GlobalStrConsts.historyClearTime)
        .then((value) {
      emit(state.copyWith(historyClearTime: value ?? "30"));
    });

    BloomeeDBService.getSettingStr(GlobalStrConsts.backupPath)
        .then((value) async {
      if (value == null || value == "") {
        await BloomeeDBService.putSettingStr(GlobalStrConsts.backupPath,
            (await getApplicationDocumentsDirectory()).path);
        emit(state.copyWith(
            backupPath: (await getApplicationDocumentsDirectory()).path));
      } else {
        emit(state.copyWith(backupPath: value));
      }
    });

    BloomeeDBService.getSettingBool(GlobalStrConsts.autoBackup).then((value) {
      emit(state.copyWith(autoBackup: value ?? false));
    });
  }

  void autoUpdate() {
    BloomeeDBService.getSettingBool(GlobalStrConsts.autoBackup).then((value) {
      if (value != null || value == true) {
        BloomeeDBService.createBackUp();
      }
    });
  }

  void setAutoUpdateNotify(bool value) {
    BloomeeDBService.putSettingBool(GlobalStrConsts.autoUpdateNotify, value);
    emit(state.copyWith(autoUpdateNotify: value));
  }

  void setAutoSlideCharts(bool value) {
    BloomeeDBService.putSettingBool(GlobalStrConsts.autoSlideCharts, value);
    emit(state.copyWith(autoSlideCharts: value));
  }

  void setDownPath(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.downPathSetting, value);
    emit(state.copyWith(downPath: value));
  }

  void setDownQuality(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.downQuality, value);
    emit(state.copyWith(downQuality: value));
  }

  void setYtDownQuality(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.ytDownQuality, value);
    emit(state.copyWith(ytDownQuality: value));
  }

  void setStrmQuality(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.strmQuality, value);
    emit(state.copyWith(strmQuality: value));
  }

  void setYtStrmQuality(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.ytStrmQuality, value);
    emit(state.copyWith(ytStrmQuality: value));
  }

  void setBackupPath(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.backupPath, value);
    emit(state.copyWith(backupPath: value));
  }

  void setAutoBackup(bool value) {
    BloomeeDBService.putSettingBool(GlobalStrConsts.autoBackup, value);
    emit(state.copyWith(autoBackup: value));
  }

  void setHistoryClearTime(String value) {
    BloomeeDBService.putSettingStr(GlobalStrConsts.historyClearTime, value);
    emit(state.copyWith(historyClearTime: value));
  }

  Future<void> resetDownPath() async {
    String? path;

    await getDownloadsDirectory().then((value) {
      if (value != null) {
        path = value.path;
        log(path.toString(), name: 'SettingsCubit');
      }
    });

    if (path != null) {
      BloomeeDBService.putSettingStr(GlobalStrConsts.downPathSetting, path!);
      emit(state.copyWith(downPath: path));
      log(path.toString(), name: 'SettingsCubit');
    } else {
      log("Path is null", name: 'SettingsCubit');
    }
  }
}
