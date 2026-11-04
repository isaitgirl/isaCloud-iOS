//
//  MLConnectTiming.h
//  monalxmpp
//
//  isaCloud: mede o tempo de cada tentativa de conexão XMPP por conta: consulta SRV, socket, TLS,
//  login, bind, resume do Stream Management, catchup e o momento em que a conta fica ociosa (o que
//  faz o spinner sumir). É só observação: não muda timers, prazos nem a ordem das etapas.
//  Cada tentativa vira uma linha em <grupo>/Library/metrics/connects-AAAA-MM-DD.jsonl, gravada uma vez,
//  quando a conta fica ociosa ou quando a tentativa termina antes disso.
//  Fica no monalxmpp (e não no app) porque o xmpp.m está nele.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MLConnectTiming : NSObject

//isaCloud: MetricsCollector passes its launch reference (CACurrentMediaTime() at launchStarted), to report since_launch_ms
+(void) setLaunchStart:(double) launchStart;

//isaCloud: reason of the next attempt of this account: "launch", "foreground", "network", "reconnect" or "other"
//(consumed by the next beginForAccount:, default "reconnect")
+(void) setReason:(NSString*) reason forAccount:(NSNumber*) accountID;

//isaCloud: starts an attempt. Returns an inert object when running inside an app extension (nothing is written from there)
+(instancetype) beginForAccount:(NSNumber*) accountID server:(NSString* _Nullable) server background:(BOOL) background;

//isaCloud: first occurrence of a stage in this attempt (dns, tcp, tls, login, resumed, bound, catchup, idle); later calls are ignored
-(void) mark:(NSString*) name;

//isaCloud: ends the attempt and writes its record (once; later calls are ignored). outcome: idle, login_timeout, disconnected or error
-(void) finishWithOutcome:(NSString*) outcome;

@end

NS_ASSUME_NONNULL_END
