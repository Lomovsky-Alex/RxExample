//
//  DocuSignService.swift
//
//  Created by Алекс Ломовской on 28.04.2022.
//

import Foundation
import UIKit
import AuthenticationServices
import RxSwift
import RxCocoa
import PDFKit

// MARK: - Protocol
protocol DocuSignManager {
  var bag: DisposeBag { get }
  var error: Driver<String> { get }
  var isWorking: Driver<Bool> { get }
  var templatePDF: Driver<PDFDocument> { get }
  var templateToShareData: Driver<Data> { get }
  var signingURL: Driver<URL> { get }
  
  var authorizeUserEvent: BehaviorEvent { get }
  var showTemplatePreviewEvent: PublishRelay<String> { get }
  var loadTemplateForSharingEvent: BehaviorEvent { get }
  var envelopeSigningData: AnyObserver<SignEnvelopeRequestDTO?> { get }
}

// MARK: - DocuSignManager
final class DocuSignManagerImpl: DocuSignManager {
  private let docuSignService: DocuSignService = DocuSignServiceImpl()
  private let fileStorageManager: FileStorageManager = FileStorageManagerImpl()
  
  init() {
    
    bindEvents()
  }
  
  // MARK: - Events
  let bag = DisposeBag()
  let authorizeUserEvent = BehaviorEvent()
  let showTemplatePreviewEvent = PublishRelay<String>()
  let loadTemplateForSharingEvent = BehaviorEvent()
  
  private let envelopeSigningDataSubject = BehaviorSubject<SignEnvelopeRequestDTO?>(value: nil)
  var envelopeSigningData: AnyObserver<SignEnvelopeRequestDTO?> {
    return envelopeSigningDataSubject
      .asObserver()
  }
  private let isWorkingSubject = PublishSubject<Bool>()
  var isWorking: Driver<Bool> {
    return Driver<Bool>.merge([
      isWorkingSubject
        .asDriver(onErrorJustReturn: false),
      docuSignService.isLoading
        .asDriver(onErrorJustReturn: false)
    ])
  }
  private let errorSubject = BehaviorSubject<String?>(value: nil)
  var error: Driver<String> {
    return errorSubject
      .asDriver(onErrorJustReturn: nil)
      .unwrap()
  }
  private let templatePDFSubject = BehaviorSubject<PDFDocument?>(value: nil)
  var templatePDF: Driver<PDFDocument> {
    return templatePDFSubject
      .asDriver(onErrorJustReturn: nil)
      .unwrap()
  }
  private let templateToShareDataSubject = BehaviorSubject<Data?>(value: nil)
  var templateToShareData: Driver<Data> {
    return templateToShareDataSubject
      .asDriver(onErrorJustReturn: nil)
      .unwrap()
  }
  private let signingURLSubject = BehaviorSubject<URL?>(value: nil)
  var signingURL: Driver<URL> {
    return signingURLSubject
      .asDriver(onErrorJustReturn: nil)
      .unwrap()
  }
  
  // MARK: - Private
  private let accessTokenSubject = BehaviorSubject<String>(value: "")
  private let accountIDSubject = BehaviorSubject<String>(value: "")
}

// MARK: - Binding
private extension DocuSignManagerImpl {
  func bindEvents() {
    bindAuthorizeUserEvent()
    bindAccessCode()
    bindSignEnvelopeEvent()
    bindShowTemplatePreviewEvent()
    bindShareTemplateEvent()
  }
  
  // MARK: - Bind accessCode
  func bindAuthorizeUserEvent() {
    let accessTokenObservable = authorizeUserEvent
      .asObservable()
      .flatMap { [weak self] _ -> Observable<BaseResponseDTO<String>> in
        guard let self = self else { return Observable.empty() }
        return self.docuSignService.getAccessToken()
      }
      .materialize()
      .share()
    
    accessTokenObservable
      .errors()
      .map { $0.localizedDescription }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    accessTokenObservable
      .elements()
      .map { $0.errorMessage }
      .unwrap()
      .filter { $0.isNotEmpty }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    accessTokenObservable
      .elements()
      .map { $0.data }
      .unwrap()
      .bind(to: accessTokenSubject)
      .disposed(by: bag)
    
    
  }
  
  // MARK: - Bind AccessToken
  func bindAccessCode() {
    let accountIDObservable = accessTokenSubject
      .filter { $0.isNotEmpty }
      .do(onNext: { token in
        KeyChainStorageManager.shared.set(string: token, forKey: Constants.PersistantStores.Keychain.docuSignToken)
      })
      .flatMap { [weak self] _ -> Observable<BaseResponseDTO<String>> in
        guard let self = self else { return Observable.empty() }
        return self.docuSignService.getAccountID()
      }
      .materialize()
      .share()
    
    accountIDObservable
      .errors()
      .map { $0.localizedDescription }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    accountIDObservable
      .elements()
      .map { $0.errorMessage }
      .unwrap()
      .filter { $0.isNotEmpty }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    accountIDObservable
      .elements()
      .map { $0.data }
      .unwrap()
      .bind(to: accountIDSubject)
      .disposed(by: bag)
  }
  
  
  // MARK: - SignEnvelope
  func bindSignEnvelopeEvent() {
    let signingURLObservable = envelopeSigningDataSubject
      .unwrap()
      .asObservable()
      .flatMap { [weak self] data -> Observable<BaseResponseDTO<String>> in
        guard let self = self else { return Observable.empty() }
        return self.docuSignService.getSigningURL(for: data)
      }
      .materialize()
      .share()
    
    signingURLObservable
      .errors()
      .map { $0.localizedDescription }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    signingURLObservable
      .elements()
      .map { $0.errorMessage }
      .unwrap()
      .filter { $0.isNotEmpty }
      .bind(to: errorSubject)
      .disposed(by: bag)
    
    signingURLObservable
      .elements()
      .map { $0.data }
      .unwrap()
      .map { URL(string: $0) }
      .bind(to: signingURLSubject)
      .disposed(by: bag)
  }
  
  // MARK: - TemplatePreview
  func bindShowTemplatePreviewEvent() {
    let localPDFObservable = showTemplatePreviewEvent
      .map { [weak self] id in
        try? self?.fileStorageManager.retrieveData(
          Constants.PersistantStores.FileStorage.agreementTemplate + id,
          from: .documents
        )
      }
      .do(onError: { error in
        Log.e(error)
      })
        .catchAndReturn(nil)
        .share()
        
        localPDFObservable
        .unwrap()
        .map { PDFDocument(data: $0) }
        .bind(to: templatePDFSubject)
        .disposed(by: bag)
    
    localPDFObservable
      .nilOnly()
      .withLatestFrom(showTemplatePreviewEvent.asObservable(), resultSelector: { ($1) })
      .filter { $0.isNotEmpty }
      .flatMap { [weak self] id  -> Observable<Bool> in
        guard let self = self else { return Observable.empty() }
        return self.docuSignService.loadTemplatePDF(
          allocationRequest: id
        )
      }
      .do { error in
        Log.e(error)
      }
      .catchAndReturn(false)
      .trueOnly()
      .withLatestFrom(showTemplatePreviewEvent.asObservable(), resultSelector: { ($1) })
      .map { [weak self] id in
        try? self?.fileStorageManager.retrieveData(
          Constants.PersistantStores.FileStorage.agreementTemplate + id,
          from: .documents
        )
      }
      .unwrap()
      .map { PDFDocument(data: $0) }
      .bind(to: templatePDFSubject)
      .disposed(by: bag)
  }
  
  // MARK: - ShareTemplate
  func bindShareTemplateEvent() {
    let localPDFDataObservable = loadTemplateForSharingEvent
      .do(onNext: { [weak self] _ in
        self?.isWorkingSubject.onNext(true)
      })
      .map { [weak self] _ in
        try? self?.fileStorageManager.retrieveData(
          Constants.PersistantStores.FileStorage.agreementTemplate,
          from: .documents
        )
      }
      .do(onError: { error in
        Log.e(error)
      })
        .catchAndReturn(nil)
        .share()
        
        localPDFDataObservable
        .unwrap()
        .bind(to: templateToShareDataSubject)
        .disposed(by: bag)
          
          localPDFDataObservable
          .unwrap()
          .map { _ in false }
          .bind(to: isWorkingSubject)
          .disposed(by: bag)
        
        localPDFDataObservable
        .nilOnly()
        .withLatestFrom(showTemplatePreviewEvent.asObservable(), resultSelector: { ($1) })
        .filter { $0.isNotEmpty }
        .flatMap { [weak self] id  -> Observable<Bool> in
          guard let self = self else { return Observable.empty() }
          return self.docuSignService.loadTemplatePDF(
            allocationRequest: id
          )
        }
        .do { error in
          Log.e(error)
        }
        .catchAndReturn(false)
        .withLatestFrom(showTemplatePreviewEvent.asObservable(), resultSelector: { ($1) })
        .map { [weak self] id in
          try? self?.fileStorageManager.retrieveData(
            Constants.PersistantStores.FileStorage.agreementTemplate + id,
            from: .documents
          )
        }
        .bind(to: templateToShareDataSubject)
        .disposed(by: bag)
  }
}
