//
//  MLLongLog.h
//  monalxmpp
//
//  isaCloud: log longo opcional, para depuração. Fica DESLIGADO por padrão (chave IsaCloudLogLongo no defaultsDB
//  do grupo de apps); só liga pela tela de Depuração. Quando ligado, cada processo (app e extensão de notificação)
//  grava um segundo log em texto puro, filtrado, em <grupo>/Library/logs-long/{app,appex}/ (arquivos de 25 MB,
//  até 40 arquivos ou 1 GB, rotação a cada 24 h). O rawlog continua igual.
//  Vale a partir da próxima abertura do app (o log é configurado no início de cada processo).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLLongLog : NSObject

//isaCloud: YES when the owner turned the long log on in the debug screen (IsaCloudLogLongo)
+(BOOL) isEnabled;

//isaCloud: called once at the end of configureLogging in each process; does nothing when the long log is off
+(void) startIfEnabled;

//isaCloud: joins the long logs of app and extension from the last `hours` hours (plus the newest file of each),
//writes them to one plain file in NSTemporaryDirectory() and returns it gzipped. nil when there is no file.
+(NSURL* _Nullable) exportForHours:(NSInteger) hours;

@end

NS_ASSUME_NONNULL_END
